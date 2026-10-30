import sys, pathlib, hashlib, argparse
import torch, coremltools as ct
from coremltools.models.neural_network.quantization_utils import quantize_weights
parser=argparse.ArgumentParser(description='Convert pinned Lightweight OpenPose to Core ML. Requires torch==2.5.1 coremltools==8.3.0 numpy<2.')
parser.add_argument('--upstream',type=pathlib.Path,required=True)
parser.add_argument('--checkpoint',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,required=True)
args=parser.parse_args()
if hashlib.sha256(args.checkpoint.read_bytes()).hexdigest() != '517c86f769c6636583083f1467e3d212a0006c27109edb3aeffc19a79622d411':
    raise SystemExit('Checkpoint digest mismatch')
sys.path.insert(0,str(args.upstream))
from models.with_mobilenet import PoseEstimationWithMobileNet

torch.set_num_threads(2)
net=PoseEstimationWithMobileNet()
ckpt=torch.load(args.checkpoint,map_location='cpu',weights_only=True)
net.load_state_dict({key: ckpt['state_dict'][key] for key in net.state_dict()},strict=True)
net.eval()
class FinalStage(torch.nn.Module):
    def __init__(self): super().__init__(); self.pose=net
    def forward(self,x):
        values=self.pose(x)
        return values[-2], values[-1]
model=FinalStage().eval()
traced=torch.jit.trace(model,torch.zeros(1,3,256,456))
ml=ct.convert(traced,convert_to='neuralnetwork',minimum_deployment_target=ct.target.macOS11,
    inputs=[ct.ImageType(name='image',shape=(1,3,256,456),color_layout=ct.colorlayout.BGR,scale=1/256,bias=[-.5,-.5,-.5])],
    outputs=[ct.TensorType(name='heatmaps'),ct.TensorType(name='pafs')])
ml=quantize_weights(ml,nbits=16)
ml.author='Lightweight OpenPose contributors; Core ML conversion for Still'
ml.license='Apache-2.0; see LICENSE-OpenPose.txt'
ml.short_description='Lightweight OpenPose (Osokin 2018), final-stage COCO keypoint heatmaps and part-affinity fields. Not a medical model.'
ml.user_defined_metadata['upstream_commit']='d23c284b09acf27a163e1febd511e7482cac25ed'
ml.user_defined_metadata['checkpoint_sha256']=hashlib.sha256((args.checkpoint).read_bytes()).hexdigest()
output=args.output
ml.save(str(output))
print('SAVED',output,output.stat().st_size,hashlib.sha256(output.read_bytes()).hexdigest())
