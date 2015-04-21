#!/bin/bash

# Command syntax: ./make-test.sh <log_output_dir> <input_for_mr_job> <output_for_mr_job>
export USER=`whoami`                 # Username to use with key. This user should be able to run tcpdump
export KEY="input/shk_eurecom.pem"   # Key to access each host. Should be one key only.
export CLUSTER="input/servers.lst"   # List of host in the cluster
export MAPFILE="input/map.txt"       # for replacing server name by number to display on y-axis 
export DATAOUT="output/job$1"
export PACKAGE_COLLECT="FALSE"       # TRUE or FALSE, remember to use upper case
if [ $2 ]; then
    export INPUT="$2"
else
    export INPUT="/user/$USER/datainput/"    # Default input for job
fi
if [ $3 ]; then
    export OUTPUT="$3"
else
    export OUTPUT="/user/$USER/dataoutput/"  # Default output for job
fi
runhadoopjob="hadoop jar /usr/hdp/current/hadoop-mapreduce-client/hadoop-mapreduce-examples-*.jar wordcount $INPUT $OUTPUT"
export YARNUSER=yarn
export HDFSUSER=hdfs
export YARNRM="master.novalocal"                                                     # Resource Manager Location
export HADOOPNN="master.novalocal"                                                   # Namenode Location
export YARNLOGBASE=/var/log/hadoop-yarn/yarn
export HDFSLOGBASE=/var/log/hadoop/hdfs
export DOMAINNAME=novalocal
export YARNRMLOGFILE="$YARNLOGBASE/yarn-$YARNUSER-resourcemanager-$YARNRM.log"       # On master node
export YARNNMLOGFILE="$YARNLOGBASE/yarn-$YARNUSER-nodemanager-*.$DOMAINNAME.log"     # On slave nodes
export HADOOPNNLOGFILE="$HDFSLOGBASE/hadoop-$HDFSUSER-namenode-$HADOOPNN.log"        # On master node
export HADOOPDNLOGFILE="$HDFSLOGBASE/hadoop-$HDFSUSER-datanode-*.$DOMAINNAME.log"    # On slave nodes


mkdir -p $DATAOUT
# GENERATING LOGS
if [ $PACKAGE_COLLECT = "TRUE" ]; then
    # Copy script controlling tcpdump to all the hosts in the cluster
    echo "Package collect is enable. We are setting-up tcpdump for listenning on each node."
    echo "It will cost lot of space to store dump file"
    for SERVER in `cat $CLUSTER`; do
        scp -i $KEY controltcpdump.sh $USER@$SERVER:~/controltcpdump.sh
        ssh -i $KEY $USER@$SERVER "chmod a+x controltcpdump.sh"
    done
    # Start tcpdump on all hosts
    for SERVER in `cat $CLUSTER`; do
        ssh -i $KEY $USER@$SERVER "./controltcpdump.sh start dump_$SERVER.pcap"
    done
else
    echo "Package collect is disable. We only collect log from services for each job."
fi
# Run hadoopjob
time $runhadoopjob &> /dev/stdout | tee $DATAOUT/tee.tmp
export jobid=`gawk -F "_" ' /Submitting tokens for job/ {print $(NF-1) "_" $NF}' $DATAOUT/tee.tmp`

finished=$( grep -c "Job job_$jobid completed successfully" $DATAOUT/tee.tmp )
if [ $finished -lt 1 ]; then echo 'Job fail!'; exit 1 ; fi

# Stop tcpdump on all hosts
if [ $PACKAGE_COLLECT = "TRUE" ]; then
    for SERVER in `cat $CLUSTER`; do
        ssh -i $KEY $USER@$SERVER "./controltcpdump.sh stop"
    done
fi

# COLLECTING LOGS
applicationid="application_$jobid"
if [ $PACKAGE_COLLECT = "TRUE" ]; then
    echo "Collecting all pcap files from all hosts" # Some nodes may get data from other nodes
    for SERVER in `cat $CLUSTER`; do
        scp -i $KEY $USER@$SERVER:~/dump_$SERVER.pcap $DATAOUT/dump_$SERVER.pcap
        ssh -i $KEY $USER@$SERVER "rm -f *.pcap"
        tcpdump -nn -tttt -r $DATAOUT/dump_$SERVER.pcap | sed 's/\./,/' > $DATAOUT/dump_$SERVER.log
    done
fi

# Collect ResourceManager LOGS
MAXLINE=4000 # We will take only max 4000 last lines in the logs
ssh -i $KEY $USER@$YARNRM "tail -n $MAXLINE $YARNRMLOGFILE > yarn_$YARNRM.log"
scp -i $KEY $USER@$YARNRM:~/yarn_$YARNRM.log $DATAOUT/
ssh -i $KEY $USER@$YARNRM "rm -f yarn_$YARNRM.log"

# Collect NodeManager LOGS
for SERVER in `cat $CLUSTER`; do
    file_exist=$( ssh -i $KEY $USER@$SERVER "if [ -f $YARNNMLOGFILE ]; then echo 'existed'; fi" )
    if [ "$file_exist" = "existed" ]; then
        ssh -i $KEY $USER@$SERVER "tail -n $MAXLINE $YARNNMLOGFILE > nodemanager_$SERVER.log"
        scp -i $KEY $USER@$SERVER:~/nodemanager_$SERVER.log $DATAOUT/nodemanager_$SERVER.log
        ssh -i $KEY $USER@$SERVER "rm -f nodemanager_$SERVER.log"
    else echo "Datanode log not existed on $SERVER"
    fi
    file_exist="not_existed" # reset variable
done

# Collect NameNode LOGS
ssh -i $KEY $USER@$HADOOPNN "tail -n $MAXLINE $HADOOPNNLOGFILE > namenode_$HADOOPNN.log"
scp -i $KEY $USER@$HADOOPNN:~/namenode_$HADOOPNN.log $DATAOUT/
ssh -i $KEY $USER@$HADOOPNN "rm -f namenode_$HADOOPNN.log"

# Collect DataNode LOGS
for SERVER in `cat $CLUSTER`; do
    file_exist=$( ssh -i $KEY $USER@$SERVER "if [ -f $HADOOPDNLOGFILE ]; then echo 'existed'; fi" )
    if [ "$file_exist" = "existed" ]; then
        ssh -i $KEY $USER@$SERVER "tail -n $MAXLINE $HADOOPDNLOGFILE > datanode_$SERVER.log"
        scp -i $KEY $USER@$SERVER:~/datanode_$SERVER.log $DATAOUT/datanode_$SERVER.log
        ssh -i $KEY $USER@$SERVER "rm -f datanode_$SERVER.log"
    else echo "Datanode log not existed on $SERVER"
    fi
    file_exist="not_existed" # reset variable
done

# Parsing containers' logs
# Using "yarn logs -applicationId $applicationid" to get the log on HDFS
echo Collect application logs from HDFS...
applicationlog="$DATAOUT/$applicationid.log" # Log from all container will be stored here
yarn logs -applicationId $applicationid > $applicationlog 2> /dev/null
# List of containers and servers executing them
grep "Container:" $applicationlog | cut -d' ' -f2,4 --output-delimiter='_' | cut -d'_' -f1,2,3,4,5,6 > $DATAOUT/containername
grep "Container:" $applicationlog | cut -d' ' -f2,4,6 --output-delimiter='_' | cut -d'_' -f7 > $DATAOUT/container_server
# Starting line of each container
grep -n "Container:" $applicationlog | cut -d':' -f1 > $DATAOUT/lineindexstart   # Find where the container's log start
tail -n +2 $DATAOUT/lineindexstart | gawk '{print $1-1}' > $DATAOUT/lineindexend # Find where the container's log end
wc -l $applicationlog | cut -d' ' -f1 >> $DATAOUT/lineindexend
paste -d' ' $DATAOUT/containername $DATAOUT/lineindexstart $DATAOUT/lineindexend $DATAOUT/container_server > $DATAOUT/containers # Merge to onefile
rm -f $DATAOUT/containername $DATAOUT/lineindexstart $DATAOUT/lineindexend $DATAOUT/container_server
echo Seperate each container\'s logs to one syslog file
while read containerinfo; do
    containername=`echo "$containerinfo" | gawk '{print $1}'`
    servername=`echo "$containerinfo" | gawk '{print $4}'`
    startline=`echo "$containerinfo" | gawk '{print $2}'`
    endline=`echo "$containerinfo" | gawk '{print $3}'`
    sed -n "${startline},${endline}p" $applicationlog > $DATAOUT/${containername}_${servername}.log
    num=`grep -n -m 3 "Log Contents:" $DATAOUT/${containername}_${servername}.log | cut -d':' -f1 | tail -n 1 | gawk '{ print $1+1 }'`
    tail -n +$num $DATAOUT/${containername}_${servername}.log > $DATAOUT/${containername}_${servername}.syslog
    rm -f $DATAOUT/${containername}_${servername}.log
done < $DATAOUT/containers
echo Start to process logs
./get-test.sh $jobid
