#VIRT_SYSPREP_OPERATIONS=user-account,logfiles,customize,bash-history,net-hostname,net-hwaddr,machine-id,dhcp-server-state,dhcp-client-state,yum-uuid,udev-persistent-net,tmp-files,smolt-uuid,rpm-db,package-manager-cache
VIRT_SYSPREP_OPERATIONS=user-account,logfiles,bash-history,machine-id
# Using cdimage.debian.org instead of cloud.debian.org subdomain for better CircleCI connectivity
BASE_URL=https://cdimage.debian.org/images/cloud/trixie/latest/
DOWNLOAD_FILE=debian-13-generic-${ARCH}.qcow2
AMD64_SHA512SUM=0449ce335d0780af6290dd0b1c11c1e5231a73a3a1fc3e49ba8172853d26f5002e02830352d91ab9894442d29c8d352b21cb6c1c29f3b0f995d968ae4b573452
ARM64_SHA512SUM=7218e35ab4abae997d57104bfe826cd15dc3979a9f0237c4e885fc113f07d5cfd800ea16798ee849a1f4c7c7428b6897c23944f1139fa7c8875b3e1b8218a13f
