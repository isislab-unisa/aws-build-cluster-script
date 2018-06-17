
# AWS Build Cluster Script

This script allows you to to configure and build a EC2 instances cluster machine on Amazon Web Service.
It arises for educational purposes to speed up and automate the creation of a cluster.

An Amazon AWS account is needed, also AWS Educate should works.


## Dependencies

To use this script you must have AWS CLI and jq 

1. Install the **AWS CLI**, see [here](https://docs.aws.amazon.com/cli/latest/userguide/installing.html)
   If you don't have it, you must install Python.
   Test if it works with the following command:

   ```bash
   $ aws --version
   ```

   The output should be somethings like this:

   ```bash
   aws-cli/1.15.21 Python/2.7.12 Linux/4.13.0-43-generic botocore/1.10.21
   ```

2. Config your CLI running 'aws configure', see [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html).
   When it asks you "Default output format" you must enter '**json**' (this script work with json).

3. Install the **jq** command

   On Ubuntu-based you can install it with the command

   ```bash
   $ sudo apt install jq
   ```

   On a generic Linux distro, you can also compile and install the source-code from [here](https://github.com/stedolan/jq)

   On Mac you can use the following command:

   ```bash
   $ brew install jq
   ```

   If it has been successful running this command you can see something like that:

   ```bash
   $ jq --version
   jq-1.5-1-a5b5cbe
   ```

## Config the script

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

4. Choose the type of machine to use in the cluster

   Now you can choose what kind of machine: you must take note of the code name.
   See the [catalog](https://aws.amazon.com/ec2/instance-types/)


## Create a cluster

To create the cluster you can run a wizard helps you asking all the information needed to create it or running the script with params.

### Wizard Mode

For example, suppose you want to create a cluster MPI of 8 instance of type t2.micro and you want create a dedicated user *pcpc* with password *test*.

Now supposing you found the *StarCluster Base Ubuntu* image with id "ami-52a0c53b".
Another important information that is required is to insert the *user access*, that is the user who is enabled by ssh, which usually for AMI Ubuntu Linux of Amazon is "ubuntu".
Usually the AMI should respect the username defined by the [Amazon guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstancesLinux.html) but may vary according to the AMI provider (so in any case contact him)

We therefore create a security group and a key-pair (or use an existing one): in this example the security group is "sg-acbb05e4" and the name of the key-pair is "kcluster"

Now you can run "./make_cluster.sh". When required insert the information required as you can see below:

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

Supposing you want to create the previous cluster, you can simply run the following command to create the cluster:

```bash
./make_cluster.sh ami-52a0c53b ubuntu sg-acbb05e4 t2.micro kcluster 3 pcpc test
```

Obviously the key.pem file must still be in the key folder.


## Manage the cluster

With the script "status_cluster.sh" you can *stop*, *start*, and *terminate* the cluster or you can simply get information on the status of the instances.

So if you want to stop all the instances without destroy the cluster (the instances are NOT in *terminated* status), you can run this command:

```bash
./state_cluster.sh stop
```

When you want, you can start the instances again with the command:

```bash
./state_cluster.sh start
```

If you want to destroy the cluster, you can run the command:

```bash
./state_cluster.sh terminate
ARE YOU SURE to TERMINATE the cluster? [y/n] : y
```

After this command all cluster instances change state to terminate making the machines irrecoverable. So for security reason the script asks you if you are sure to do it.

To get information on the status of the instances present in the cluster, run the following command:

```bash
./state_cluster.sh info
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

This script was tested by building a cluster of size 8 using AMI StarCluster ami-52a0c53b (Linux Ubuntu) on T2.Micro and M4.Large (using the commands shown for the MPI cluster example) and it should work with all Ubuntu-based AMIs.


## Author

This tool was designed and developed by [Sergio Guastaferro](https://github.com/labgua) during the course of Concurrent and Parallel Programming on Cloud to automate the process of creating clusters.
