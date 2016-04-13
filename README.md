# Installing DeepLearning4j 

TBD

## Usage

TBD

```
juju deploy --constraints "instance-type=g2.2xlarge" trusty/ubuntu ubuntu-gpu
```

Then install and expose the nvidia-docker charm 

```
juju deploy cs:~samuel-cozannet/trusty/nvidia-docker
juju add-relation ubuntu-gpu nvidia-docker
juju expose nvidia-docker
```
