[中文](README.md) / English
<p align="left">
    <a href="https://opensource.org/licenses/Apache-2.0" alt="License">
        <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" /></a>
<a target="_blank" href="https://join.slack.com/t/neatlogichome/shared_invite/zt-1w037axf8-r_i2y4pPQ1Z8FxOkAbb64w">
<img src="https://img.shields.io/badge/Slack-Neatlogic-orange" /></a>
</p>

## Main Features

neatlogic-autoexec-backend is a backend execution tool for automation runners. It is used to execute automation jobs,
receive job scheduling instructions from the control server, execute operations based on job parameters provided by the
control server and operation parameters provided by the target nodes, and callback the status to the server.

## Arguments

```shell
usage: autoexec [-h] [-v] [--jobid JOBID] [--execuser EXECUSER] [--paramsfile PARAMSFILE]
                [--nodesfile NODESFILE] [--force] [--firstfire] [--abort] [--pause]
                [--register REGISTER] [--cleanstatus] [--purgejobdata PURGEJOBDATA] [--devmode]
                [--nofirenext] [--passthroughenv PASSTHROUGHENV] [--phasegroups PHASEGROUPS]
                [--phases PHASES] [--nodes NODES] [--sqlfiles SQLFILES]

optional arguments:
  -h, --help            show this help message and exit
  -v, --verbose         Automation Runner
  --jobid JOBID, -j JOBID
                        Job id for this execution
  --execuser EXECUSER, -u EXECUSER
                        Operator
  --paramsfile PARAMSFILE, -p PARAMSFILE
                        Params file path for this execution
  --nodesfile NODESFILE, -n NODESFILE
                        Nodes file path for this execution
  --force, -f           Force to run all nodes regardless of the node status
  --firstfire, -i       The first phase fired, create a new log file
  --abort, -k           Abort the job
  --pause, -s           Pause the job
  --register REGISTER, -r REGISTER
                        Register all tools to the tenant
  --cleanstatus, -c     Clean all job stats
  --purgejobdata PURGEJOBDATA
                        Job reserve days
  --devmode, -d         Develop test in command line
  --nofirenext          Do not fire the next job phase
  --passthroughenv PASSTHROUGHENV
                        Additional JSON parameter while callback to console
  --phasegroups PHASEGROUPS
                        Just execute specified group
  --phases PHASES       Just execute defined phases. Example: phase1,phase2
  --nodes NODES         Just execute defined node ids. Example: 463104705880067,463104705880068
  --sqlfiles SQLFILES   Example: [{"sqlFile": "mydb.myuser/1.test.sql", "nodeName": "myNode", "nodeType": "MySQL", "resourceId": 1343434, "host": "xx.yy.zz.uu", "port": 22, "accessEndpoint": null, "username": "dbuser"},...]
```

## Usage

### After installing python3 on Linux, change the default python interpreter to python3

Execute the setup.sh script in the autoexec directory to switch the default python interpreter to python3.
If the

target machine cannot access the Internet, download the RPM package and its dependencies using a package management tool
like yum on a Linux machine of the same version, and then copy them to the target machine for installation.

```shell
cd autoexec
bin/setup.sh
```

### Set up the installation user for passwordless sudo

Edit the /etc/sudoers file using the root user and add the following content:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:
Add the following content to the /etc/sudoers file using the root user:

```shell
app ALL=(root) NOPASSWD:ALL
```

### Install Python third-party libraries

If the target installation machine cannot access the Internet, execute the installation on a Linux machine of the same
version that can access the Internet, and then package the autoexec/plib directory and copy it to the target machine.

```
cd autoexec/media
./ins-modules.sh
```

### Upgrade Python third-party libraries

```
cd autoexec/media
./upgrade-modules.sh
```

### Reinstall a single module

```
cd autoexec/media
./ins-modules.sh ijson
./upgrade-modules.sh ijson
```

Python third-party libraries will be installed in the autoexec/plib directory.

### Install Perl third-party libraries required for local tools

```shell
cd autoexec/plugins/local/media
./setup.sh
```

### Reinstall specific Perl third-party libraries required for local tools

- Example: Installing Config-Tiny-2.28 and XML-Simple-2.22.tar

```shell
cd autoexec/plugins/local/media
./setupone.sh Net-SSLeay-1.92 Config-Tiny-2.28 XML-Simple-2.22
```

Perl third-party libraries will be installed in autoexec/plugins/local/pllib.

### VSCode Settings

- Set up .vscode/settings.json (refer to test/examples-files/settings.json)
- Set up .vscode/launch.json (for Python and Perl debugging, refer to test/examples-files/launch.json)
- Set up Python environment variables (refer to test/examples-files/.penv, which will be referenced by settings.json)
- Copy the above three files to the .vscode directory of your project and modify them according to the actual
  directories.

### Development Debugging Mode

- Run debugging

```shell
# Set environment variables
# Set tenant environment variable tenant, taking the develop tenant as an example
export TENANT=develop
# Set the Passthrough JSON, the runnerId attribute is required, query the ID corresponding to the current runner through the runner management page
export PASSTHROUGH_ENV='{"runnerId":1}'
# Set the Python lib directory
export AUTOEXEC_HOME=/app/autoexec
export PYTHONPATH=$AUTOEXEC_HOME/plugins/local/lib:$AUTOEXEC_HOME/lib:$AUTOEXEC_HOME/plib
export PERL5LIB=$AUTOEXEC_HOME/plugins/local/lib:$AUTOEXEC_HOME/plugins/local/lib/perl-lib/lib

/perl5
```

```shell
# When using devmode, the server will not be updated or data retrieved. It will only execute the job based on the information in the nodes.json and params.json files in the job directory.
$ python3 bin/autoexec --jobid 3247896236758

$ python3 bin/autoexec --devmode --paramsfile test/params.json --nodesfile test/nodes.json

$ python3 bin/autoexec --devmode --jobid 97867868 --nodesfile test/nodes.json

$ python3 bin/autoexec --devmode --jobid 97867868 --paramsfile test/params.json
```

> Note:
>
> * If no jobid is specified, the default jobid 0 will be used.
> * If no paramsfile is set, the jobid needs to be specified to tell autoexec which job's runtime parameters to
    download.
> * If no nodes.json file is set and the "runNode" property is not present in the paramsfile, the jobid needs to be
    specified to tell autoexec which job's target nodes to download. Otherwise, autoexec will assume there are no target
    nodes to run.
> * If running in test mode or the current process is associated with a TTY, autoexec's console output logs will be
    directly printed to the console. If running in production mode, console output will be written to log files. Logs
    related to target execution will be written to individual log files for each target, regardless of the mode.

- Example of VSCode launch.json configuration

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "autoexec",
      "type": "python",
      "request": "launch",
      "program": "${workspaceFolder}/bin/autoexec",
      "env": {
        "RUNNER_ID": "1",
        "TENANT": "develop",
        "PASSTHROUGH_ENV": "{\"runnerId\":1}"
      },
      "args": [
        "--jobid",
        "623789909794820",
        "--firstfire",
        "--execuser",
        "fccf704231734072a1bf80d90b2d1de2",
        "--passthroughenv",
        "{\"runnerId\":1}",
        "--paramsfile",
        "${workspaceFolder}/test/params.json",
        "--nodesfile",
        "${workspaceFolder}/test/nodes.json"
      ],
      "console": "integratedTerminal"
    },
    {
      "name": "autoexec-abort",
      "type": "python",
      "request": "launch",
      "program": "${workspaceFolder}/bin/autoexec",
      "env": {
        "RUNNER_ID": "1",
        "TENANT": "develop",
        "PASSTHROUGH_ENV": "{\"runnerId\":1}"
      },
      "args": [
        "--jobid",
        "623907543244820",
        "--execuser",
        "fccf704231734072a1bf80d90b2d1de2",
        "--passthroughenv",
        "{\"runnerId\":1}",
        "--abort"
      ],
      "console": "integratedTerminal"
    }
  ]
}
```

- Example of .vscode/settings.json configuration

```json
{
  "python.envFile": "/Users/wenhb/git/autoexec/.vscode/.env",
  "perltidy.profile": "/Users/wenhb/git/autoexec/.vscode/.perltidyrc",
  "perl.perlInc": [
    ".",
    "/Users/wenhb/git/autoexec/plugins/remote/wastool/bin",
    "/Users

    /wenhb/git/autoexec/plugins/local/build/lib
    ",
    "/Users/wenhb/git/autoexec/plugins/local/deploy/lib",
    "/Users/wenhb/git/autoexec/plugins/local/pllib/lib/perl5",
    "/Users/wenhb/git/autoexec/plugins/local/lib",
    "/Users/wenhb/git/autoexec/plugins/remote/lib",
    "/Users/wenhb/git/autoexec/plugins/remote/cmdbcollect/lib"
  ],
  "java.configuration.updateBuildConfiguration": "interactive"
}
```

### Production Mode

- Register built-in tools

```shell
$ python3 bin/autoexec --register tenant_name
```

*Registers the local and remote tools under the autoexec to a specific tenant, where tenant_name is the name of the
tenant.*

- Run a job

```shell
$ python3 bin/autoexec --jobid "2983676" --execuser "admin" --paramsfile "params.json"
```

*In production mode, you need to provide the --jobid, --execuser, and --paramsfile parameters. During the job execution,
when a node finishes its execution or a phase completes, a callback will be made to the backend server to update the
corresponding status.*

- Abort a job

```shell
$ python3 bin/autoexec --jobid "2983676" --abort
```

*Stops the execution of a job. Use --jobid to specify the job number to stop. The aborted nodes will be reported to the
backend server with the status "Aborted".*
*Return values: 0: successful stop; 1: failed to stop; 2: job does not exist.*

- Pause a job

```shell
python3 bin/autoexec --jobid "2983676" --pause
```

*Pauses the execution of a job. Use --jobid to specify the job number to pause. The scheduler will wait until the most
recent node execution is completed.*
*Return values: 0: successfully paused; 1: failed to pause; 2: job does not exist*

- Clean up the job's status records

```shell
python3 bin/autoexec --jobid "374288003424256" --cleanstatus
```

*After a job is executed, it stores the status of each node. Nodes that have been successfully executed will not be
executed again. If you need to clear the status records for testing purposes, you can execute this command.*

## Directory Structure Overview

### Program Files

- bin/autoexec

*Main program responsible for parameter processing and initialization of job execution environment variables and other
information.*

- lib/VContext.py
- lib/Context.py
  *VContext.py is the parent class of Context.py.*
  *Stores all runtime-related information and passes it between different environments. The information includes job ID,
  execution user, paths for logs and status, status of each phase, MongoDB connection, etc.*

- lib/AutoexecError.py

*Exception handling class for execution.*

- lib/NodeStatus.py

*Enumeration class for node status.*

- lib/Operation.py

*Class for operation information, used to record attributes related to an operation and prepare for its execution. This
includes downloading file parameters, resolving parameter references, and generating command lines for the operation.*

- lib/OutputStore.py

*Stores the output of each execution node in MongoDB and loads it from MongoDB.*

- lib/PhaseExecutor.py

*Executor for each phase. Each phase will create a thread pool, read the node information to generate RunNode objects,
and assign them to the threads in the thread pool for execution.*

- lib/PhaseStatus.py

*Records the execution status of each phase, including the number of successful nodes, failed nodes, and ignored nodes.*

- lib/RunNode.py

*Execution node, responsible for running all operations of a specific phase based on the parameters and node type. It
also records the status and output of the node.*

- lib/RunNodeFactory.py

*Iterator for node information files.*

- lib/ServerAdapter.py

*Adapter class for backend server interface. All calls to the backend server go through this class.*

- lib/TagentClient.py

*Python implementation of the Tagent Client.*

- lib/Utils.pm

*Utility class that stores all small shareable methods.*

### Runtime Data and Log Directories

- data

*Root directory for storing all job data.*

- data/cache

*Cache directory for downloaded files of file-type parameters. Files are saved with their file ID as the name. When
downloading files, the "lastModified" attribute is sent to the server. If there are no modifications, the server returns
a 304 status. The job creates hard links to these files in this directory.*

- data/job/xxx/yyy/zzz

*Job's runtime directory. "xxx/yyy/zzz" represents the job ID split into three-byte subdirectories. This is done to
avoid having too many files and directories in a single subdirectory, which could impact performance.*

- data/job/xxx/yyy/zzz/file

*Directory for storing file-type parameters needed for job execution. Hard links are created to the cache directory
mentioned above.*

- data/job/xxx/yyy/zzz/log

*Location for saving logs of each phase execution. Each node has its own log file.*
*For example: data/job/xxx/yyy/zzz/log/post

, where "post" is the phase name. data/job/xxx/yyy/zzz/log/post/192.168.0.1-22.txt, where "192.168.0.1" is the node's IP
and "22" is the node's port. data/job/xxx/yyy/zzz/log/post/192.168.0.1-22.hislog/20210521-112018.anonymous.txt is the
historical log file for the node, and the log file name includes the start time of the execution, the execution user,
and the last modification time of the file, which is the end time of the execution.*

- data/job/xxx/yyy/zzz/output

*Directory for node outputs. It stores the output file for each node. For example: 192.168.0.22-3939.json. The content
is a sample like:*

- i18n

*Stores data structure descriptions for various objects used in CMDB auto collection.*
*Importing CMDB and inspection object descriptions:*

```shell
cd autoexec
source ./setenv.sh
cd autoexec/i18n/cmdbcollect
python3 dicttool 
```

- plugins/local

*Directory for built-in tools that run on the runner. Each subdirectory represents a tool group, and within each group,
there are multiple tools. Each tool consists of an implementation program and a JSON description file.*

- plugins/remote

*Directory for built-in tools that run on the target OS. Each subdirectory represents a tool group, and within each
group, there are multiple tools. Each tool consists of an implementation program and a JSON description file.*

```json
{
  "localdemo": {
    "outtext": "this is the text out value",
    "outfile": "this is the output file name",
    "outjson": "{\"key1\":\"value1\", \"key2\":\"value2\"}",
    "outcsv": "\"name\",\"sex\",\"age\"\\n\"\u5f20\u4e09\u201c,\"\u7537\u201c,\"30\"\\n\"\u674e\u56db\",\"\u5973\u201c,\"35\"",
    "outpassword": "{RC4}xxxxxxxxxx"
  },
  "localremotedemo_tttt": {
    "outfile": "this is the output file name",
    "outtext": "this is the text out value",
    "outpassword": "{RC4}xxxxxxxxxx",
    "outcsv": "\"name\",\"sex\",\"age\"\\n\"\u5f20\u4e09\u201c,\"\u7537\u201c,\"30\"\\n\"\u674e\u56db\",\"\u5973\u201c,\"35\"",
    "outjson": "{\"key1\":\"value1\", \"key2\":\"value2\"}"
  },
  "remotedemo_34234": {
    "outcsv": "\"name\",\"sex\",\"age\"\\n\"\u00e5\u00bc\u00a0\u00e4\u00b8\u0089\u00e2\u0080\u009c,\"\u00e7\u0094\u00b7\u00e2\u0080\u009c,\"30\"\\n\"\u00e6\u009d\u008e\u00e5\u009b\u009b\",\"\u00e5\u00a5\u00b3\u00e2\u0080\u009c,\"35\"",
    "outjson": "{\"key1\":\"value1\", \"key2\":\"value2\"}",
    "outfile": "this is the output file name",
    "outpassword": "{RC4}xxxxxxxxxx",
    "outtext": "this is the text out value"
  }
}
```

- data/job/xxx/yyy/zzz/status

*Directory for storing the running status of each node and associated operations. Each node has its own status file. For
example: post/192.168.0.22-3939.json (the execution status of node 192.168.0.22:3939 in the "post" phase). Sample
content:

```json
{
  "status": "succeed",
  "localremotedemo_tttt": "succeed",
  "remotedemo_34234": "succeed"
}
```

## Sample Parameter File

```json
{
  "jobId": 624490098515988,
  "roundCount": 64,
  "opt": {},
  "runFlow": [
    {
      "execStrategy": "oneShot",
      "groupNo": 0,
      "phases": [
        {
          "operations": [
            {
              "output": {},
              "opt": {},
              "opName": "shell countdown",
              "opType": "runner",
              "is

              Script
              ": 1,
              "opId": "shell countdown_624490098515994",
              "interpreter": "bash",
              "failIgnore": 1,
              "desc": {}
            }
          ],
          "phaseName": "oneshot_local"
        },
        {
          "operations": [
            {
              "output": {},
              "opt": {},
              "opName": "shell countdown_target",
              "opType": "target",
              "isScript": 1,
              "opId": "shell countdown_target_624490098515998",
              "interpreter": "bash",
              "failIgnore": 1,
              "desc": {}
            }
          ],
          "phaseName": "oneshot_target"
        }
      ]
    },
    {
      "execStrategy": "grayScale",
      "groupNo": 1,
      "phases": [
        {
          "operations": [
            {
              "output": {},
              "opt": {},
              "opName": "shell countdown",
              "opType": "runner",
              "isScript": 1,
              "opId": "shell countdown_624490098516001",
              "interpreter": "bash",
              "failIgnore": 1,
              "desc": {}
            }
          ],
          "execRound": "first",
          "phaseName": "grayscale_local"
        },
        {
          "operations": [
            {
              "output": {},
              "opt": {},
              "opName": "shell countdown_target",
              "opType": "target",
              "isScript": 1,
              "opId": "shell countdown_target_624490098516163",
              "interpreter": "bash",
              "failIgnore": 1,
              "desc": {}
            }
          ],
          "phaseName": "grayscale_target"
        }
      ]
    },
    {
      "execStrategy": "oneShot",
      "groupNo": 2,
      "phases": [
        {
          "operations": [
            {
              "output": {},
              "opt": {},
              "opName": "shell countdown",
              "opType": "runner",
              "isScript": 1,
              "opId": "shell countdown_624490098516166",
              "interpreter": "bash",
              "failIgnore": 1,
              "desc": {}
            }
          ],
          "phaseName": "oneshot_local2"
        }
      ]
    }
  ],
  "arg": {},
  "execUser": "system",
  "tenant": "develop"
}
```

Explanation:

- "jobId": Job ID. If the defined value is different from the "--jobid" command-line argument of autoexec, it will be
  forcefully changed to match.
- "roundCount": Number of groups for grouped execution
- "preJobId": ID of the previous job, used for passing in when connecting multiple jobs in an ITSM process. It will be
  passed back to the control backend during the callback. (deprecated)
- "runNode": If this property is present, the running target will be based on it, and autoexec will not call the API to
  obtain the target nodes required for execution.
- "opt": List of input parameters for the entire job, structured as key-value pairs.
- "runFlow": An array structure that includes multiple run groups. Each element in the array represents a run group,
  where the key is the name of the run phase, and the content of the run phase consists of an array of multiple
  operations. Multiple phases within a run group will run concurrently.
- The parameter "isScript" in the operation: It indicates whether the operation is a custom script. If "isScript" is 1,
  there must be another parameter "scriptId" that provides the script ID so that autoexec can download the script from
  the control backend based on the script ID.

## Sample nodes file

```json
{
  "resourceId": 456,
  "nodeName": "myhost",
  "nodeType": "host",
  "host": "192.168.0.27",
  "protocol": "ssh",
  "protocolPort": 22,
  "username": "root",
  "password": "xxxxxx"
}
{
  "resourceId": 567,
  "nodeName": "tomcat1",
  "nodeType": "tomcat",
  "host": "192.168.0.22",
  "protocol": "tagent",
  "protocolPort": 3939,
  "port": 8080,
  "username": "root",
  "password": "{RC4}xxxxxxx"
}
{
  "resourceId": 458,
  "nodeName": "tomcat2",
  "nodeType": "tomcat",
  "host": "192.168.0.26",
  "protocol": "tagent",
  "protocolPort": 3939,
  "port": 8080,
  "username": "root",
  "password": "xxxxxxxx"
}

```

Additional explanation:

- "resourceId": UUID of the target node to be executed
- "nodeName": Node name (not necessarily unique)
- "nodeType": Method of connecting to the node
- "host": IP address of the target to connect to
- "port": Port of the target node (the combination of IP and service port determines a target node)
- "protocol": Protocol for remote operations on the node, ssh｜tagent
- "protocolPort": Port corresponding to the connection protocol
- "username": OS user running the tool on the target node
- "password": Password for connecting to the target node

## Setting SSH Trust between Runners (SSH Trust is Required for Artifact Synchronization)

### Steps to set up SSH Trust

Choose one of the runners, log in as the app user, and use the "ssh-keygen" tool to generate an RSA public key and
private key:

```shell
ssh-keygen
cd ~/.ssh
scp id_rsa id_rsa.pub app@xx.yy.zz.w1:.ssh/
scp id_rsa id_rsa.pub app@xx.yy.zz.w2:.ssh/
scp id_rsa id_rsa.pub app@xx.yy.zz.w3:.ssh/
...

# Use the app user to log in to each runner separately
# Execute the following command on all runners to append the public key to the file ~/.ssh/authorized_keys
cat id_rsa.pub >> authorized_keys
chmod

 600 authorized_keys
chmod 600 id_rsa

# Verify the passwordless login between each pair of runners
```

## Installing the Agent Tool (sshcmd)

### Single Target

```shell
python3 bin/sshcmd --host 192.168.0.26 --port 2020 --user root --password ********  ls -l /tmp
python3 bin/sshcmd --host 192.168.0.26 --user root --password ********  ls -l /tmp
```

### Multiple Targets

Create a file "/tmp/hosts.txt" and add the following content:

```shell
192.168.0.26:22 root password
192.168.0.25:22 root password
```

```shell
python3 bin/sshcmd --hostsfile /tmp/hosts.txt ls -l /tmp
```

Create a file "/tmp/hosts1.txt" and add the following content:

```shell
192.168.0.26:22 password
192.168.0.25:22 password
```

```shell
python3 bin/sshcmd --user root --hostsfile /tmp/hosts1.txt ls -l /tmp
```

Create a file "/tmp/hosts2.txt" and add the following content:

```shell
192.168.0.26:22
192.168.0.25:22
```

```shell
python3 bin/sshcmd --user root --password ****** --hostsfile /tmp/hosts1.txt ls -l /tmp
```