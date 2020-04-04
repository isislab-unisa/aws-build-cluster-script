#!/bin/bash

PIDS=""
TIME_POLLING=3
SSH_ATTEMPTS=3 # 30 is way too much when multiplied for timeout
NAME_FILE_PEM=*.pem
LOCAL_PEM_AMAZON=key/$NAME_FILE_PEM
VERSIONING_MASTER_URL=https://raw.githubusercontent.com/isislab-unisa/aws-build-cluster-script/master/VERSION
this_version=$(cat VERSION)
PHASE=""
SPLASH=0
SPLASH_SCREEN="\n====================================================\n"
SPLASH_SCREEN="${SPLASH_SCREEN}\tAWS Build Cluster Script $this_version\n"
SPLASH_SCREEN="${SPLASH_SCREEN}\tCreate a simple cluster on AWS\n"
SPLASH_SCREEN="${SPLASH_SCREEN}\tSergio Guastaferro, 2018 [labgua]\n"
SPLASH_SCREEN="${SPLASH_SCREEN}\tSimone Bisogno, 2020 [bissim]\n"
SPLASH_SCREEN="${SPLASH_SCREEN}====================================================\n"

## custom defined functions
checkBGProcesses() {
	for p in $PIDS
	do
		if wait $p
		then
			echo > /dev/null
		else
			echo -e "\nAn error occurred for process $p"
			echo "Failed phase: $PHASE"
			exit
		fi
	done
}

checkError() {
	local error_code=$1

	if (( $error_code != 0 ))
	then
		## interrupt script execution, any subsequent phase would fail anyway
		echo
		echo "An error occurred while connecting to one or more instances."
		echo "Please check thoroughly CLI configuration or EC2 Security Group settings."
		echo "A common solution would be creating a new Security Group."
		echo
		echo "Failed phase: $PHASE."
		exit
	fi
}

announcePhase() {
	PHASE=$1

	echo ">>> $PHASE..."
}

announcePhaseTermination() {
	echo -e ">>> $PHASE: DONE\n"
}

## cheking updates
last_version=$(curl -s -L $VERSIONING_MASTER_URL)
last_version="${last_version//./}"
this_version="${this_version//./}"
#echo "last version: $last_version"
#echo "this version: $this_version"
if [[ $last_version > $this_version ]]
then
	echo -e "\nA new version of AWS Build Cluster Script is available!\n"
fi
this_version=$(cat VERSION)


if [[ $# = 0 ]]; 
then
	echo -e "$SPLASH_SCREEN"
	echo "Insert all the information required."

	read -p "AMI             : " AMI
	read -p "USER_ACCESS     : " USER_ACCESS
	read -p "SECURITY_GROUP  : " SECURITY_GROUP
	read -p "INSTANCE_TYPE   : " INSTANCE_TYPE
	read -p "KEY_NAME        : " KEY_NAME
	read -p "DIM_CLUSTER     : " DIM_CLUSTER
	read -p "USERNAME        : " CUSER
	read -p "PASSWORD        : " CPASS
	echo

	SPLASH=1
elif [ $# = 1  ] && [ $1 = "--version" ]
then
	cat VERSION
	echo
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
	echo -e "\tRun the wizard for create the cluster"
	echo "$0 <AMI> <USER_ACCESS> <SECURITY_GROUP> <INSTANCE_TYPE> <KEY_NAME> <DIM_CLUSTER> <USERNAME> <PASSWORD>" 
	echo -e "\tParametric mode to create the cluster"
	echo "$0 --version"
	echo -e "\tGet the version of the script in use"
	exit
fi

## clean environment
rm data/* > /dev/null

if (( SPLASH == 0 ))
then
	echo -e "$SPLASH_SCREEN"
fi

announcePhase "Creating a cluster of $DIM_CLUSTER instances"

aws ec2 run-instances --image-id $AMI --security-group-ids $SECURITY_GROUP \
--count $DIM_CLUSTER --instance-type $INSTANCE_TYPE --key-name $KEY_NAME \
--query 'Instances[*].InstanceId' \
> data/id_instances.json
checkError $?

## check whether aws command failed
if [[ ! -s data/id_instances.json ]]; then
	## aws may indeed creates the file even if it fails to create cluster
	echo -e "An error occurred while requesting instances.\n" \
		"Please check AWS CLI configuration or parameters provided" \
		"in this wizard."
	exit
fi
echo "Saved instances IDs on data/id_instances.json"
announcePhaseTermination

## list id instances
id_instances=( $(jq -r '.[]' data/id_instances.json) )
id_inst_params=""
for each in "${id_instances[@]}"
do
  id_inst_params="$id_inst_params $each"
done

announcePhase "Waiting for instances to become RUNNING"

#unready_machines=0
ready_machines=0
while [[ $ready_machines != $DIM_CLUSTER ]]; do

	aws ec2 describe-instance-status --instance-ids $id_inst_params \
	--query "InstanceStatuses[*].InstanceState.Name" \
	> data/status_instances.json
	checkError $?

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
echo "All instances are in 'running' state!"
announcePhaseTermination

announcePhase "Getting instances public and private IPs"

aws ec2 describe-instances --instance-ids $id_inst_params \
--query 'Reservations[0].Instances[*].PublicIpAddress' \
>> data/ip_list.json
checkError $?

aws ec2 describe-instances --instance-ids $id_inst_params \
--query 'Reservations[0].Instances[*].PrivateIpAddress' \
>> data/ip_private_list.json
checkError $?
echo "Saved on data/ip_list.json and data/ip_private_list.json"
announcePhaseTermination

## list ip instances
ip_list=( $(jq -r '.[]' data/ip_list.json) )
ip_private_list=( $(jq -r '.[]' data/ip_private_list.json) )

## save simple array for master in remote, [for mpirun]
set | grep ^ip_private_list= > data/ip_private_list.array

## save simple array with public IPs as well (MASTER is the first IP)
set | grep ^ip_list= > data/ip_list.array

## setting MASTER
MASTER=${ip_list[0]}

announcePhase "Checking SSH connections on instances"

for pub_ip in "${ip_list[@]}"
do
	ssh -oStrictHostKeyChecking=no -oConnectionAttempts=$SSH_ATTEMPTS -i $LOCAL_PEM_AMAZON $USER_ACCESS@$pub_ip "exit;" &
	PIDS+=" $!"
#	checkError $?
	echo "$pub_ip is READY!"
done
checkBGProcesses
announcePhaseTermination

announcePhase "Configuring MASTER::$MASTER"

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
checkError $?
announcePhaseTermination

announcePhase "Configuring SLAVES"

PIDS=""
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_slave_ip=${ip_list[$i]}

	slave_conf="sudo useradd -s /bin/bash -m -d /home/$CUSER -g root $CUSER; \
	sudo mkdir -p /home/$CUSER/.ssh; \
	sudo chown $CUSER:root ../$CUSER/.ssh; \
	echo -e \"$CPASS\n$CPASS\n\" | sudo passwd $CUSER;"

	ssh -oStrictHostKeyChecking=no -i $LOCAL_PEM_AMAZON $USER_ACCESS@$curr_slave_ip "$slave_conf" &
	PIDS+=" $!"
#	checkError $?
done
checkBGProcesses
announcePhaseTermination

announcePhase "Sending PEM on MASTER::$MASTER node"

scp -i $LOCAL_PEM_AMAZON $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER:
checkError $?
announcePhaseTermination

announcePhase "Sending ip_private_list on MASTER::$MASTER node in $CUSER space... [for future automation]"

scp -i $LOCAL_PEM_AMAZON data/ip_private_list.array $USER_ACCESS@$MASTER:
checkError $?
ssh -oStrictHostKeyChecking=no -i $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER "sudo cp ip_private_list.array /home/$CUSER/"
checkError $?
announcePhaseTermination

announcePhase "Setting names in /etc/hosts for all nodes"

set_hosts="printf \"\n# AWS Build Cluster Script -- nodes private IPs\n\" | sudo tee -a /etc/hosts > /dev/null; "
set_hosts=$set_hosts"printf \"${ip_private_list[0]}   MASTER\n\" | sudo tee -a /etc/hosts > /dev/null; "
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	set_hosts=$set_hosts"printf \"${ip_private_list[$i]}   NODE_$i\n\" | sudo tee -a /etc/hosts > /dev/null; "
done

PIDS=""
for node in "${ip_list[@]}"
do
	ssh -i $LOCAL_PEM_AMAZON $USER_ACCESS@$node "$set_hosts" &
	PIDS=" $!"
#	checkError $?
done
checkBGProcesses

# print /etc/hosts from MASTER instead of printing all the ones from every node
echo "Updated /etc/hosts file:"
ssh -i $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER "cat /etc/hosts;"
checkError $?
announcePhaseTermination

announcePhase "Sending id_rsa and id_rsa.pub from MASTER to SLAVES"

PIDS=""
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_private_slave_ip=${ip_private_list[$i]}
	send_rsa="sudo scp -oStrictHostKeyChecking=no -i $NAME_FILE_PEM ../$CUSER/.ssh/id_rsa ../$CUSER/.ssh/id_rsa.pub $USER_ACCESS@$curr_private_slave_ip:"

	ssh -i $LOCAL_PEM_AMAZON $USER_ACCESS@$MASTER "$send_rsa" &
	PIDS+=" $!"
#	checkError $?
done
checkBGProcesses
announcePhaseTermination

announcePhase "Moving and setting permission for PEM files on slaves"

PIDS=""
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_slave_ip=${ip_list[$i]}

	slave_pem_conf="sudo chown $CUSER:root id_rsa id_rsa.pub; \
	sudo chmod -R 777 /home/$CUSER/.ssh; \
	sudo mv id_rsa id_rsa.pub /home/$CUSER/.ssh; \
	sudo -u $CUSER cp /home/$CUSER/.ssh/id_rsa.pub /home/$CUSER/.ssh/authorized_keys; \
	sudo chown $CUSER:root /home/$CUSER/.ssh/authorized_keys; \
	sudo chmod -R 700 /home/$CUSER/.ssh;"

	ssh -i $LOCAL_PEM_AMAZON $USER_ACCESS@$curr_slave_ip "$slave_pem_conf" &
	PIDS+=" $!"
#	checkError $?
done
checkBGProcesses
announcePhaseTermination

echo ">>> Cluster is READY!"

echo "On each instance, following user has been created:"
echo -e "USERNAME:$CUSER\nPASSWORD:$CPASS\n"

echo -e "MASTER\tIP_PUBLIC=$MASTER"
for (( i=1; i<$DIM_CLUSTER; i++ ))
do
	curr_private_slave_ip=${ip_private_list[$i]}
	curr_slave_ip=${ip_list[$i]}
	echo -e "SLAVE $i\tPRIVATE_IP=$curr_private_slave_ip\tPUBLIC_IP=$curr_slave_ip"
done
