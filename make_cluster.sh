#!/bin/bash

TIME_POLLING=3
SSH_ATTEMPTS=30
NAME_FILE_PEM=*.pem
LOCAL_PEM_AMAZON=key/$NAME_FILE_PEM
VERSIONING_MASTER_URL=https://raw.githubusercontent.com/isislab-unisa/aws-build-cluster-script/master/VERSION

##cheking updates
last_version=$(curl -s -L $VERSIONING_MASTER_URL)
last_version="${last_version//./}"
this_version=$(cat VERSION)
this_version="${this_version//./}"
#echo "last version: $last_version"
#echo "this version: $this_version"
if [[ $last_version > $this_version ]]
then
	echo "There is an UPDATE!"
fi


if [[ $# = 0 ]]; 
then
	echo "===================================================="
	echo "  AWS Build Cluster Script"
	echo "  Create a simple cluster on AWS"
	echo "  Sergio Guastaferro, 2018 [labgua]"
	echo "===================================================="

	echo "Insert all the information required."

	read -p "AMI             : " AMI
	read -p "USER_ACCESS     : " USER_ACCESS
	read -p "SECURITY_GROUP  : " SECURITY_GROUP
	read -p "INSTANCE_TYPE   : " INSTANCE_TYPE
	read -p "KEY_NAME        : " KEY_NAME
	read -p "DIM_CLUSTER     : " DIM_CLUSTER
	read -p "USERNAME        : " CUSER
	read -p "PASSWORD        : " CPASS

elif [ $# = 1  ] && [ $1 = "--version" ]
then
	cat VERSION
	echo ""
	exit

elif [[ $# = 8 ]]
then
	AMI=$1
	USER_ACCESS=$2
	SECURITY_GROUP=$3
	INSTANCE_TYPE=$4
	KEY_NAME=$5
	DIM_CLUSTER=$6
	CUSER=$7
	CPASS=$8
else
	echo "USAGE"
	echo "$0"
	echo "        Run the wizard for create the cluster"
	echo "$0 <AMI> <USER_ACCESS> <SECURITY_GROUP> <INSTANCE_TYPE> <KEY_NAME> <DIM_CLUSTER> <USERNAME> <PASSWORD>" 
	echo "        Parametric mode to create the cluster"
	echo "$0 --version"
	echo "        Get the version of the script in use"
	exit
fi

## clean environment
rm data/* > /dev/null


echo ">>> Creating $DIM_CLUSTER instances..." 

aws ec2 run-instances --image-id $AMI --security-group-ids $SECURITY_GROUP \
--count $DIM_CLUSTER --instance-type $INSTANCE_TYPE --key-name $KEY_NAME \
--query 'Instances[*].InstanceId' \
>> data/id_instances.json

echo "DONE and Saved on data/id_instances.json"

## list id instances
id_instances=( $(jq -r '.[]' data/id_instances.json) )


id_inst_params=""
for each in "${id_instances[@]}"
do
  id_inst_params="$id_inst_params $each"
done


echo ">>> WAITING for the instances to become RUNNING"

#unready_machines=0
ready_machines=0
while [[ $ready_machines != $DIM_CLUSTER ]]; do

	aws ec2 describe-instance-status --instance-ids $id_inst_params \
	--query "InstanceStatuses[*].InstanceState.Name" \
	> data/status_instances.json

	status_instances=( $(jq -r '.[]' data/status_instances.json) )

	if [[ ${#status_instances[@]} = 0 ]]; then
		sleep $TIME_POLLING
		continue
	fi

	ready_machines=0
	for status in "${status_instances[@]}"; do
		if [[ status != "running" ]]; then
			ready_machines=$((ready_machines+1))
		fi
	done

	sleep $TIME_POLLING

done


echo "DONE, All Running!"


echo ">>> Getting the IPs ..." 

aws ec2 describe-instances --instance-ids $id_inst_params \
--query 'Reservations[0].Instances[*].PublicIpAddress' \
>> data/ip_list.json


aws ec2 describe-instances --instance-ids $id_inst_params \
--query 'Reservations[0].Instances[*].PrivateIpAddress' \
>> data/ip_private_list.json


echo "DONE and Saved on data/ip_list.json and data/ip_private_list.json"

## list ip instances
ip_list=( $(jq -r '.[]' data/ip_list.json) )
ip_private_list=( $(jq -r '.[]' data/ip_private_list.json) )

## save simple array for master in remote, [for mpirun]
set | grep ^ip_private_list= > data/ip_private_list.array


## setting MASTER
MASTER=${ip_list[0]}


###########NEW!!!!
echo ">>> Checking SSH connections on instances..."
for pub_ip in "${ip_list[@]}"
do
	ssh -oStrictHostKeyChecking=no -oConnectionAttempts=$SSH_ATTEMPTS -i $LOCAL_PEM_AMAZON $USER_ACCESS@$pub_ip "exit;"
	echo "$pub_ip is READY!"
done
echo "OK!"


echo ">>> Configuring the MASTER::$MASTER ..."

##config MASTER [cp al posto di cat]
master_conf="sudo useradd -s /bin/bash -m -d /home/$CUSER -g root $CUSER; \
sudo mkdir -p /home/$CUSER/.ssh; \
sudo chown $CUSER:root ../$CUSER/.ssh; \
echo -e \"$CPASS\n$CPASS\n\" | sudo passwd $CUSER; \
sudo -u $CUSER ssh-keygen -t rsa -N \"\" -C \"\" -f /home/$CUSER/.ssh/id_rsa; \
sudo -u $CUSER chmod -R 777 /home/$CUSER/.ssh; \
sudo -u $CUSER touch /home/$CUSER/.ssh/authorized_keys; \
sudo -u $CUSER chmod 777 /home/$CUSER/.ssh/authorized_keys; \
sudo -u $CUSER cp /home/$CUSER/.ssh/id_rsa.pub /home/$CUSER/.ssh/authorized_keys; \
sudo -u $CUSER chmod -R 700 /home/$CUSER/.ssh;"

ssh -oStrictHostKeyChecking=no -i $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER "$master_conf"

echo "DONE"



echo ">>> Configuring the SLAVES ..."
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_slave_ip=${ip_list[$i]}

	slave_conf="sudo useradd -s /bin/bash -m -d /home/$CUSER -g root $CUSER; \
	sudo mkdir -p /home/$CUSER/.ssh; \
	sudo chown $CUSER:root ../$CUSER/.ssh; \
	echo -e \"$CPASS\n$CPASS\n\" | sudo passwd $CUSER;"

	ssh -oStrictHostKeyChecking=no -i $LOCAL_PEM_AMAZON $USER_ACCESS@$curr_slave_ip "$slave_conf"
done

echo "DONE"


echo ">>> Sending PEM on MASTER::$MASTER node ..."
scp -i $LOCAL_PEM_AMAZON $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER:
echo "DONE"

echo ">>> Sending ip_private_list on MASTER::$MASTER node in $CUSER space... [for future automation]"
scp -i $LOCAL_PEM_AMAZON data/ip_private_list.array $USER_ACCESS@$MASTER:
ssh -oStrictHostKeyChecking=no -i $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER "sudo cp ip_private_list.array /home/$CUSER/"
echo "DONE"


echo ">>> Sending id_rsa and id_rsa.pub from MASTER to SLAVEs ..."
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_private_slave_ip=${ip_private_list[$i]}
	send_rsa="sudo scp -oStrictHostKeyChecking=no -i $NAME_FILE_PEM ../$CUSER/.ssh/id_rsa ../$CUSER/.ssh/id_rsa.pub $USER_ACCESS@$curr_private_slave_ip:"

	ssh -i $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER "$send_rsa"
done

echo "DONE"


echo ">>> Moving and Set permission for PEM file on slaves..."
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_slave_ip=${ip_list[$i]}

	slave_pem_conf="sudo chown $CUSER:root id_rsa id_rsa.pub; \
	sudo chmod -R 777 /home/$CUSER/.ssh; \
	sudo mv id_rsa id_rsa.pub /home/$CUSER/.ssh; \
	sudo -u $CUSER cp /home/$CUSER/.ssh/id_rsa.pub /home/$CUSER/.ssh/authorized_keys; \
	sudo chown $CUSER:root /home/$CUSER/.ssh/authorized_keys; \
	sudo chmod -R 700 /home/$CUSER/.ssh;"

	ssh -i $LOCAL_PEM_AMAZON $USER_ACCESS@$curr_slave_ip "$slave_pem_conf"
done


echo ">>> The Cluster is READY!"

echo "On each instance there is a user with :"
echo "USERNAME:$CUSER - PASSWORD:$CPASS"

echo -e "MASTER\t IP_PUBLIC=$MASTER"
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_private_slave_ip=${ip_private_list[$i]}
	curr_slave_ip=${ip_list[$i]}
	echo -e "SLAVE $i\tPRIVATE_IP=$curr_private_slave_ip \tPUBLIC_IP=$curr_slave_ip"
done