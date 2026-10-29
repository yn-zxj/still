package local.still.link;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.view.Gravity;
import android.widget.*;
import java.util.ArrayList;

public class MainActivity extends Activity {
    private TextView heart, status, course;
    private Button toggle, pause, end;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable refresh = new Runnable() { public void run() {
        LinkService service = LinkService.current;
        heart.setText(service != null && service.freshBpm() > 0 ? String.valueOf(service.freshBpm()) : "—");
        status.setText(service == null ? LinkService.lastStatus : service.status);
        boolean active = service != null && service.hasSession();
        course.setText(active ? service.title + "\n" + service.remaining / 60 + ":" + String.format("%02d", service.remaining % 60) : "在息间选择休息课程");
        toggle.setText(service == null ? "开始连接" : "停止连接");
        pause.setEnabled(active); end.setEnabled(active);
        pause.setText(active && service.phase.equals("P") ? "继续" : "暂停");
        handler.postDelayed(this, 1000);
    }};
    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true); scroll.setBackgroundColor(Color.rgb(247,248,252));
        LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); layout.setGravity(Gravity.CENTER); layout.setPadding(dp(24),dp(32),dp(24),dp(28));
        scroll.addView(layout);
        TextView logo = text("息间 · Still Link", 16, Color.rgb(120,100,217)); layout.addView(logo);
        heart = text("—", 52, Color.rgb(41,40,62)); layout.addView(heart);
        layout.addView(text("次 / 分钟",12,Color.rgb(125,124,145)));
        status = text("准备连接", 13, Color.rgb(76,140,120)); status.setPadding(0,dp(12),0,dp(8)); layout.addView(status);
        course = text("在息间选择休息课程",15,Color.rgb(41,40,62)); course.setPadding(0,dp(10),0,dp(14)); layout.addView(course);
        LinearLayout controls = new LinearLayout(this); controls.setGravity(Gravity.CENTER);
        pause = button("暂停",false); end = button("结束",false); controls.addView(pause); controls.addView(end); layout.addView(controls);
        pause.setOnClickListener(v -> { LinkService s=LinkService.current; if(s!=null) s.command(s.phase.equals("P")?"resume":"pause"); });
        end.setOnClickListener(v -> { LinkService s=LinkService.current; if(s!=null) s.command("end"); });
        toggle = button("开始连接",true); layout.addView(toggle); toggle.setOnClickListener(v -> {
            if(LinkService.current != null) stopService(new Intent(this,LinkService.class)); else startLink();
        });
        setContentView(scroll);
    }
    private void startLink() {
        ArrayList<String> missing = new ArrayList<>();
        if(checkSelfPermission(Manifest.permission.BODY_SENSORS)!=PackageManager.PERMISSION_GRANTED) missing.add(Manifest.permission.BODY_SENSORS);
        if(Build.VERSION.SDK_INT>=31) for(String p:new String[]{Manifest.permission.BLUETOOTH_ADVERTISE,Manifest.permission.BLUETOOTH_CONNECT}) if(checkSelfPermission(p)!=PackageManager.PERMISSION_GRANTED) missing.add(p);
        if(!missing.isEmpty()) { requestPermissions(missing.toArray(new String[0]),1); return; }
        BluetoothAdapter adapter = ((android.bluetooth.BluetoothManager)getSystemService(BLUETOOTH_SERVICE)).getAdapter();
        if(adapter==null || !adapter.isEnabled()) { LinkService.lastStatus="请先打开手表蓝牙"; return; }
        try { startForegroundService(new Intent(this,LinkService.class)); } catch(Exception e) { LinkService.lastStatus="无法启动，请重新打开应用"; }
    }
    @Override public void onRequestPermissionsResult(int r,String[] p,int[] grants) {
        super.onRequestPermissionsResult(r,p,grants);
        if(r==1) { for(int g:grants) if(g!=PackageManager.PERMISSION_GRANTED) { LinkService.lastStatus="需要传感器与蓝牙权限"; return; } startLink(); }
    }
    @Override protected void onResume() { super.onResume(); handler.post(refresh); }
    @Override protected void onPause() { handler.removeCallbacks(refresh); super.onPause(); }
    private int dp(int v) { return (int)(v*getResources().getDisplayMetrics().density); }
    private TextView text(String t,int size,int color) { TextView v=new TextView(this); v.setText(t);v.setTextSize(size);v.setTextColor(color);v.setGravity(Gravity.CENTER);v.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));return v; }
    private Button button(String title,boolean primary) {
        Button b=new Button(this);b.setText(title);b.setTextSize(14);b.setAllCaps(false);b.setTextColor(primary?Color.WHITE:Color.rgb(92,71,189));
        GradientDrawable bg=new GradientDrawable();bg.setColor(primary?Color.rgb(120,100,217):Color.rgb(238,235,250));bg.setCornerRadius(dp(30));b.setBackground(bg);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(primary?dp(170):dp(80),dp(43));lp.setMargins(dp(4),dp(6),dp(4),dp(6));b.setLayoutParams(lp);return b;
    }
}
