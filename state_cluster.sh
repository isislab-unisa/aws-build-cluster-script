#!/bin/bash

if [[ $# != 1 ]]; then
	echo "USAGE:"
	echo "$0 {start|stop|terminate|info}"
	echo
	echo "$0 start"
	echo "        Start the cluster previously stopped"
	echo "$0 stop"
	echo "        Stop the cluster currently running"
	echo "$0 terminate"
	echo "        Terminate the cluster: ALL DATA ON INSTANCES WILL BE LOST!"
	echo "$0 info"
	echo "        Get the status of cluster instances"
	exit
fi


echo ">>>>>> Loading instances from data/id_instances.json"
## LOADING list id instances
id_instances=( $(jq -r '.[]' data/id_instances.json) )
echo "DONE"

id_inst_params=""
for each in "${id_instances[@]}"
do
  id_inst_params="$id_inst_params $each"
done

choose=$1

case "$choose" in
	terminate)
		read -p "ARE YOU SURE you want to TERMINATE the cluster? [y/n] : " confirm

		if [[ $confirm != "y" ]]
		then
			echo "Operation aborted!"
			exit
		fi

		echo ">>>>>> Terminating instances from Amazon EC2"
		aws ec2 terminate-instances --instance-ids $id_inst_params
		echo "DONE"

		## clean environment
		rm data/*
		;;
	stop)
		echo ">>>>>> Stopping instances from Amazon EC2"
		aws ec2 stop-instances --instance-ids $id_inst_params
		echo "DONE"
		;;
	start)
		echo ">>>>>> Starting instances from Amazon EC2"
		aws ec2 start-instances --instance-ids $id_inst_params
		echo "DONE"
		;;
	info)
		aws ec2 describe-instance-status --instance-ids $id_inst_params
		;;
	*)
		echo "Action $1 not valid"
esac