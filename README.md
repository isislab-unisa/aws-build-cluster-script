# AWS Build Cluster Script

This script allows you to to configure and build an EC2 instances cluster on Amazon Web Service.
It arises for educational purposes to speed up and automate the creation of a cluster.

An Amazon AWS account is needed (AWS Educate accounts work as well).

## Dependencies

To use this script you must have AWS CLI and `jq` installed 

1. Install the **AWS CLI**, see [official documentation](https://docs.aws.amazon.com/cli/latest/userguide/installing.html)
   For AWS CLI v1, if you don't have it, you must install Python; for v2 all required tools are self-contained.
   Test if it works by launching the following command:

   ```bash
   $ aws --version
   ```

   The output should be somethings like this:

   ```bash
   aws-cli/1.15.21 Python/2.7.12 Linux/4.13.0-43-generic botocore/1.10.21
   ```

2. Config your CLI running 'aws configure', see [official documentation](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html).
   When it asks you "Default output format" you must enter '**json**' (this script work with json).
   
   **Important** - *see this example*
   
   ```bash
   $ aws configure
   AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
   AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   Default region name [None]: us-west-1
   Default output format [None]: json
   ```

   You may also edit `~/.aws/credentials` and `~/.aws/config` files by hand, especially if you're using an AWS Educate account with third-party hosted labs providing pre-formatted credentials.

3. Install the **jq** command

   On Ubuntu-based distributions, you can install it with the command

   ```bash
   $ sudo apt install jq
   ```

   On a generic Linux distro, you can also compile and install the source code from [the official repository](https://github.com/stedolan/jq).

   On Mac you can use the Brew tool:

   ```bash
   $ brew install jq
   ```

   Check for installation success:

   ```bash
   $ jq --version
   jq-1.5-1-a5b5cbe
   ```

## Configure the script

1. Recover the information needed to make the cluster: [*Security-Group*](https://console.aws.amazon.com/ec2/v2/home#SecurityGroups:), [*key-pairs*](https://console.aws.amazon.com/ec2/v2/home#KeyPairs:sort=keyName)
   Take note of the id of the security group and the name of the key pair you want to use.
   So download the file.pem associated with the new keypair ( or take the old file.pem ) and copy it into the "key" directory

2. Now set the permission file on PEM in key directory:

	```bash
	$ chmod 700 key/*.pem
	```

3. If it is not possible for security reasons, make the downloaded files executable so run:

	```bash
	$ chmod +x make_cluster.sh state_cluster.sh
	```

## Create a cluster

To create a cluster, you can either run a wizard which helps you asking all the information needed to create it or running the script with params.

### Wizard Mode

For example, suppose you want to create an MPI cluster of 8 type `t2.micro` (for other instance types, check the [catalog](https://aws.amazon.com/ec2/instance-types/)) instances and you want to create a dedicated user *pcpc* with password *test*.

Suppose you want to use the *StarCluster Base Ubuntu* image, which AMI ID is `ami-52a0c53b`.
Another important information that is required is to insert the *user access*, that is the user who is enabled to use ssh, which usually for AMI Ubuntu Server of Amazon is "ubuntu".
Usually the AMI should respect the username defined by the [Amazon guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstancesLinux.html) but it may vary according to the AMI provider (so in any case contact it).

We therefore create a security group and a key pair (or use an existing one): in this example the security group is `sg-acbb05e4` and the name of the key pair is `kcluster`

Now you can run `./make_cluster.sh` with no arguments. When required, insert needed information as you can see below:

```bash
$ ./make_cluster.sh
====================================================
  AWS Build Cluster Script
  Create a simple cluster on AWS
  Sergio Guastaferro, 2018 [labgua]
====================================================
Insert all the information required.
AMI             : ami-52a0c53b
USER_ACCESS     : ubuntu
SECURITY_GROUP  : sg-acbb05e4
INSTANCE_TYPE   : t2.micro
KEY_NAME        : kcluster
DIM_CLUSTER     : 8
USERNAME        : pcpc
PASSWORD        : test
```

### Parametric Mode

Suppose you want to create a cluster with previous settings, you can simply run the following command:

```bash
$ ./make_cluster.sh ami-52a0c53b ubuntu sg-acbb05e4 t2.micro kcluster 3 pcpc test
```

Obviously, the PEM file associated to `kcluster` key must still be in the `key/` folder.

### Slave Nodes IPs Management  

After running the script, each node has a friendly name: assuming we have a cluster composed of `n` nodes, the master name is `MASTER` and each slave is named `NODE_j` where `j` ranges in [1; n-1].
For example, in a cluster of 3 nodes we have `MASTER`, `NODE_1` and `NODE_2`

Furthermore, both methods create a bash array containing all cluster nodes private IPs, called `ip_private_list.array`.
The first element of this array is the private ip of the master node and the remaining IPs are the ones of slave nodes
This array can be used as follows:

```bash
. ip_private_list.array
echo ${ip_private_list[@]} # print all the private IPs of the array
```

An operative example of such a file could be the creation of hostfiles for an MPI cluster:

```bash
. ip_private_list.array

for (( i=1; i<=${#ip_private_list[@]}; i++ ))
do
	for each in "${ip_private_list[@]:0:$i}"
	do
	  echo $each >> "myhostfile_$i"
	done
done
```

This snippet deals with creating as much hostfiles as the number of nodes in the cluster, by incrementally adding IPs in every file:

- myhostfile_1 will contain only the private IP of master;
- myhostfile_2 will contain the private IP of master and slave1;
- myhostfile_3 will contain the private IP of master, slave1 and slave2

and so on.

## Manage the cluster

With the script "status_cluster.sh" you can *stop*, *start*, and *terminate* the cluster or you can simply get information on the status of the instances.

So, if you want to stop all the instances without destroy the cluster (instances NOT in *terminated* status), you can run this command:

```bash
$ ./state_cluster.sh stop
```

Whenever you want, you can start the instances again with the command:

```bash
$ ./state_cluster.sh start
```

If you want to destroy the cluster, you can run the command:

```bash
$ ./state_cluster.sh terminate
ARE YOU SURE you want to TERMINATE the cluster? [y/n] : y
```

After this command all cluster instances change state to **terminate**, making the machines unrecoverable; that's why in this case script asks for confirmation.

To get information on the status of the instances present in the cluster, run the following command:

```bash
$ ./state_cluster.sh info
```

This command should show a json response with the state of all cluster instances.

```json
{
    "InstanceStatuses": [
        {
            "InstanceId": "i-004c50eb8136dcbf2", 
            "InstanceState": {
                "Code": 16, 
                "Name": "running"
            }, 
            "AvailabilityZone": "us-east-1d", 
            "SystemStatus": {
                "Status": "initializing", 
                "Details": [
                    {
                        "Status": "initializing", 
                        "Name": "reachability"
                    }
                ]
            }, 
            "InstanceStatus": {
                "Status": "initializing", 
                "Details": [
                    {
                        "Status": "initializing", 
                        "Name": "reachability"
                    }
                ]
            }
        }, 
        ...
    ]
}

```

## Testing

This script was tested by building a cluster of size 8 using AMI StarCluster `ami-52a0c53b` (Linux Ubuntu) on `t2.micro` and `m4.large` (using the commands shown for the MPI cluster example) and it should work with all Ubuntu-based AMIs (check compatibility between instance type and AMI beforehand).

The following table shows the other results of the tests performed on different OSes:

|      AMI     |                           AMI NAME                          | OS TYPE | INSTANCE TYPE | RESULT |
|:------------:|:-----------------------------------------------------------:|:-------:|:-------------:|:-------:|
| ami-52a0c53b |           starcluster-base-ubuntu-12.04-x86_64-hvm          |  Ubuntu |    `t2.micro`   |  WORKS  |
| ami-116d857a |         debian-jessie-amd64-hvm-2015-06-07-12-27-ebs        |  Debian |    `t2.micro`   |  WORKS  |
| ami-00035c7b | Fedora-Atomic-25-20170727.0.x86_64-us-east-1-HVM-standard-0 |  Fedora |    `t2.micro`   |  WORKS  |

## Problems & Errors
If you encounter any error, you must:

1. go to the web console and stop all (possible) active instances
2. search for issues here similar to your error
3. in case no related issue (closed or open) exists, don't refrain yourself and write an issue (Do not be afraid, I answer you as soon as I can)

## Author

This tool was designed and developed by [Sergio Guastaferro](https://github.com/labgua) in 2018, during the course of Concurrent and Parallel Programming on Cloud to automate the process of creating clusters.

Minor subsequent contributions have been apported by [Simone Bisogno](https://github.com/bissim), mainly about error handling and message formatting.
