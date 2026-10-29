package local.still.link;

import android.app.*;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.Intent;
import android.hardware.*;
import android.os.*;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Real sensor values only. One bonded central owns the session until disconnected. */
public class LinkService extends Service implements SensorEventListener {
    public static volatile LinkService current;
    public static volatile String lastStatus="点击开始，连接息间";
    public volatile String status="准备中…", title="", phase="E";
    public volatile int remaining=0;
    private volatile int bpm=0;
    private volatile long lastSensor=0, lastState=0;
    private volatile String session="-";
    private final Handler main=new Handler(Looper.getMainLooper());
    private SensorManager sensors;
    private BluetoothGattServer server;
    private BluetoothLeAdvertiser advertiser;
    private BluetoothGattCharacteristic heart, state, control;
    private BluetoothDevice owner;
    private final Set<UUID> subscriptions=new HashSet<>();
    private ByteArrayOutputStream prepared;
    private boolean advertising=false, notifying=false, commandBusy=false, linkActive=false;
    private final ArrayDeque<Message> queue=new ArrayDeque<>();
    private long launched, lastClient;
    private static final UUID HR=uuid("0000180d-0000-1000-8000-00805f9b34fb"), MEASURE=uuid("00002a37-0000-1000-8000-00805f9b34fb"), CCCD=uuid("00002902-0000-1000-8000-00805f9b34fb");
    private static final UUID STILL=uuid("782b1000-6f52-4c85-a701-596be18a7810"), STATE=uuid("782b1001-6f52-4c85-a701-596be18a7810"), CONTROL=uuid("782b1002-6f52-4c85-a701-596be18a7810");
    private static UUID uuid(String s) { return UUID.fromString(s); }
    private static class Message { BluetoothGattCharacteristic c; byte[] data; Message(BluetoothGattCharacteristic c,byte[] d){this.c=c;data=d;} }
    public int freshBpm() { return SystemClock.elapsedRealtime()-lastSensor<10000?bpm:0; }
    public boolean hasSession() { return !session.equals("-")&&!phase.equals("E")&&SystemClock.elapsedRealtime()-lastState<10000; }
    @Override public void onCreate() {
        super.onCreate(); current=this; launched=lastClient=SystemClock.elapsedRealtime();
        NotificationManager nm=getSystemService(NotificationManager.class);nm.createNotificationChannel(new NotificationChannel("link","手表连接",NotificationManager.IMPORTANCE_LOW));
        PendingIntent open=PendingIntent.getActivity(this,0,new Intent(this,MainActivity.class),PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop=PendingIntent.getService(this,1,new Intent(this,LinkService.class).setAction("stop"),PendingIntent.FLAG_IMMUTABLE);
        Notification n=new Notification.Builder(this,"link").setContentTitle("息间正在连接").setContentText("传输心率与跟练进度").setSmallIcon(android.R.drawable.ic_media_play).setContentIntent(open).setOngoing(true).addAction(new Notification.Action.Builder(null,"停止",stop).build()).build();
        try {
            startForeground(7,n);
            sensors=(SensorManager)getSystemService(SENSOR_SERVICE);Sensor sensor=sensors.getDefaultSensor(Sensor.TYPE_HEART_RATE);
            if(sensor==null) { fail("未发现心率传感器，无法启动");return; }
            BluetoothManager manager=getSystemService(BluetoothManager.class);BluetoothAdapter adapter=manager.getAdapter();
            if(adapter==null||!adapter.isEnabled()||!adapter.isMultipleAdvertisementSupported()) { fail("蓝牙未开启或不支持广播");return; }
            advertiser=adapter.getBluetoothLeAdvertiser();server=manager.openGattServer(this,callback);
            if(advertiser==null||server==null) { fail("无法创建蓝牙服务");return; }
            BluetoothGattService hs=new BluetoothGattService(HR,BluetoothGattService.SERVICE_TYPE_PRIMARY);
            heart=notifyCharacteristic(MEASURE);hs.addCharacteristic(heart);
            BluetoothGattService ss=new BluetoothGattService(STILL,BluetoothGattService.SERVICE_TYPE_PRIMARY);
            state=new BluetoothGattCharacteristic(STATE,BluetoothGattCharacteristic.PROPERTY_WRITE,BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED);
            control=notifyCharacteristic(CONTROL);ss.addCharacteristic(state);ss.addCharacteristic(control);
            pendingService=ss;
            if(!server.addService(hs)) {fail("无法注册心率服务");return;}
            if(!sensors.registerListener(this,sensor,SensorManager.SENSOR_DELAY_NORMAL)) {fail("无法读取心率传感器");return;}
            main.post(healthCheck);
        } catch(Exception e) { fail("启动失败，请检查蓝牙与传感器权限"); }
    }
    private BluetoothGattService pendingService;
    private BluetoothGattCharacteristic notifyCharacteristic(UUID id) {
        BluetoothGattCharacteristic c=new BluetoothGattCharacteristic(id,BluetoothGattCharacteristic.PROPERTY_NOTIFY,0);
        c.addDescriptor(new BluetoothGattDescriptor(CCCD,BluetoothGattDescriptor.PERMISSION_READ_ENCRYPTED|BluetoothGattDescriptor.PERMISSION_WRITE_ENCRYPTED));return c;
    }
    private void fail(String message) { lastStatus=message;status=message;stopSelf(); }
    @Override public int onStartCommand(Intent i,int flags,int startId) { if(i!=null&&"stop".equals(i.getAction())) {lastStatus="已停止连接";stopSelf();} return START_NOT_STICKY; }
    @Override public IBinder onBind(Intent i) {return null;}
    private final AdvertiseCallback adCallback=new AdvertiseCallback(){
        @Override public void onStartSuccess(AdvertiseSettings s){main.post(()->{advertising=true;status="请在 Mac 搜索手表";});}
        @Override public void onStartFailure(int code){main.post(()->fail("蓝牙广播失败（"+code+"）"));}
    };
    private final BluetoothGattServerCallback callback=new BluetoothGattServerCallback(){
        @Override public void onServiceAdded(int result,BluetoothGattService service){main.post(()->{
            if(server==null)return;
            if(result!=BluetoothGatt.GATT_SUCCESS){fail("蓝牙服务注册失败");return;}
            if(service.getUuid().equals(HR)){if(!server.addService(pendingService))fail("课程服务注册失败");return;}
            AdvertiseData data=new AdvertiseData.Builder().addServiceUuid(new ParcelUuid(HR)).build();
            // Name in scan response avoids overflowing the 31-byte legacy advertisement.
            AdvertiseData response=new AdvertiseData.Builder().addManufacturerData(0xFFFF,"Still Link".getBytes(StandardCharsets.UTF_8)).build();
            advertiser.startAdvertising(new AdvertiseSettings.Builder().setConnectable(true).setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setTimeout(0).build(),data,response,adCallback);
        });}
        @Override public void onConnectionStateChange(BluetoothDevice device,int result,int newState){main.post(()->{
            if(server==null)return;
            if(newState==BluetoothProfile.STATE_CONNECTED){
                if(owner!=null&&!owner.equals(device)){server.cancelConnection(device);return;}
                owner=device;linkActive=true;lastClient=SystemClock.elapsedRealtime();status="已连接 · 等待订阅";
                if(advertising){advertiser.stopAdvertising(adCallback);advertising=false;}
            }else if(device.equals(owner)){owner=null;linkActive=false;session="-";phase="E";subscriptions.clear();queue.clear();notifying=false;prepared=null;lastStatus="Mac 已断开，请重新连接";stopSelf();}
        });}
        @Override public void onDescriptorReadRequest(BluetoothDevice d,int id,int offset,BluetoothGattDescriptor desc){main.post(()->{
            if(server==null)return;boolean ok=authorized(d)&&offset==0;
            server.sendResponse(d,id,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION,offset,ok?(subscriptions.contains(desc.getCharacteristic().getUuid())?BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE:BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE):null);
        });}
        @Override public void onDescriptorWriteRequest(BluetoothDevice d,int id,BluetoothGattDescriptor desc,boolean prep,boolean response,int offset,byte[] value){main.post(()->{
            if(server==null)return;boolean ok=authorized(d)&&!prep&&offset==0&&desc.getUuid().equals(CCCD)&&value.length==2&&(value[0]==0||value[0]==1)&&value[1]==0;
            if(ok){if(value[0]==1)subscriptions.add(desc.getCharacteristic().getUuid());else subscriptions.remove(desc.getCharacteristic().getUuid());status="Mac 已连接";}
            if(response)server.sendResponse(d,id,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,0,null);
        });}
        @Override public void onCharacteristicWriteRequest(BluetoothDevice d,int id,BluetoothGattCharacteristic c,boolean prep,boolean response,int offset,byte[] value){main.post(()->{
            if(server==null)return;boolean ok=authorized(d)&&c.getUuid().equals(STATE);
            if(ok&&prep){if(offset==0)prepared=new ByteArrayOutputStream();ok=prepared!=null&&offset==prepared.size()&&offset+value.length<=180;if(ok)prepared.write(value,0,value.length);}
            else if(ok){ok=offset==0&&value.length<=180&&applyState(value);}
            if(response)server.sendResponse(d,id,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH,offset,prep?value:null);
        });}
        @Override public void onExecuteWrite(BluetoothDevice d,int id,boolean execute){main.post(()->{
            if(server==null)return;boolean ok=authorized(d)&&(!execute||(prepared!=null&&applyState(prepared.toByteArray())));prepared=null;
            server.sendResponse(d,id,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_FAILURE,0,null);
        });}
        @Override public void onNotificationSent(BluetoothDevice d,int result){main.post(()->{notifying=false;drain();});}
    };
    private boolean authorized(BluetoothDevice d){return owner!=null&&owner.equals(d)&&d.getBondState()==BluetoothDevice.BOND_BONDED;}
    private boolean applyState(byte[] value){
        String[] p=new String(value,StandardCharsets.UTF_8).split("\\|",4);
        if(p.length!=4||!(p[0].equals("-")||p[0].matches("[0-9a-fA-F]{8}"))||!Arrays.asList("R","P","E").contains(p[1]))return false;
        int seconds;try{seconds=Integer.parseInt(p[2]);}catch(Exception e){return false;}
        if(seconds<0||seconds>86400)return false;
        session=p[0];phase=p[1];remaining=seconds;title=p[3];lastState=SystemClock.elapsedRealtime();commandBusy=false;return true;
    }
    public void command(String action){
        if(!hasSession()||commandBusy||!Arrays.asList("pause","resume","end").contains(action))return;
        commandBusy=true;enqueue(control,(session+"|"+action).getBytes(StandardCharsets.UTF_8));main.postDelayed(()->commandBusy=false,2000);
    }
    @Override public void onSensorChanged(SensorEvent e){
        if(e.sensor.getType()!=Sensor.TYPE_HEART_RATE||e.values.length==0)return;
        int value=Math.round(e.values[0]);if(e.accuracy==SensorManager.SENSOR_STATUS_UNRELIABLE||value<1||value>300){bpm=0;return;}
        bpm=value;lastSensor=SystemClock.elapsedRealtime();
        byte[] data=value>255?new byte[]{1,(byte)(value&255),(byte)(value>>8)}:new byte[]{0,(byte)value};enqueue(heart,data);
    }
    @Override public void onAccuracyChanged(Sensor s,int accuracy){if(accuracy==SensorManager.SENSOR_STATUS_UNRELIABLE)bpm=0;}
    private void enqueue(BluetoothGattCharacteristic c,byte[] data){
        if(owner==null||!subscriptions.contains(c.getUuid()))return;
        queue.removeIf(m->m.c==c);queue.add(new Message(c,data));drain();
    }
    private void drain(){
        if(notifying||server==null||owner==null||queue.isEmpty())return;
        Message m=queue.remove();m.c.setValue(m.data);notifying=server.notifyCharacteristicChanged(owner,m.c,false);
    }
    private final Runnable healthCheck=new Runnable(){public void run(){
        long now=SystemClock.elapsedRealtime();
        if(!linkActive&&now-launched>120000){lastStatus="搜索超时，已停止传感器";stopSelf();return;}
        if(linkActive&&subscriptions.isEmpty()&&now-lastClient>30000){lastStatus="订阅超时，已停止连接";stopSelf();return;}
        if(!session.equals("-")&&now-lastState>=10000){phase="E";session="-";status="课程连接中断";}
        if(linkActive&&freshBpm()==0)status="已连接 · 等待真实心率";
        main.postDelayed(this,1000);
    }};
    @Override public void onDestroy(){
        main.removeCallbacksAndMessages(null);
        if(sensors!=null)sensors.unregisterListener(this);
        try{if(advertiser!=null&&advertising)advertiser.stopAdvertising(adCallback);if(server!=null){if(owner!=null)server.cancelConnection(owner);server.close();}}catch(Exception ignored){}
        server=null;owner=null;queue.clear();bpm=0;current=null;stopForeground(STOP_FOREGROUND_REMOVE);super.onDestroy();
    }
}
