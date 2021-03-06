#!/bin/bash
########################### 
# program start.sh is the script that initiates the execution of the variant calling pipeline
# to run this program type this command from a head node that can launch PBS-Torque qsub jobs:
# start.sh <runfile>
###########################
#redmine=hpcbio-redmine@igb.illinois.edu
redmine=grendon@illinois.edu
if [ $# != 1 ]
then
        MSG="Parameter mismatch."
        echo -e "program=$0 stopped. Reason=$MSG" | mail -s "Variant Calling Workflow failure message" "$redmine"
        exit 1;
fi

echo -e "\n\n############# BEGIN VARIANT CALLING WORKFLOW ###############\n\n"
umask 0027
set -x
echo `date`	
scriptfile=$0
runfile=$1

set +x; echo -e "\n\n############# CHECKING PARAMETERS ###############\n\n"; set -x;

if [ !  -s $runfile ]
then
	MSG="$runfile configuration file not found."
	echo -e "program=$0 stopped. Reason=$MSG" | mail -s "Variant Calling Workflow failure message" "$redmine"
	exit 1;
fi

set +x
echo -e "\n\n####################################################################################################" >&2
echo        "##################################### PARSING RUN INFO FILE ########################################" >&2
echo        "##################################### AND SANITY CHECK      ########################################" >&2
echo -e "\n\n####################################################################################################\n\n" >&2; set -x;


reportticket=$( cat $runfile | grep -w REPORTTICKET | cut -d '=' -f2 )
outputdir=$( cat $runfile | grep -w OUTPUTDIR | cut -d '=' -f2 )
email=$( cat $runfile | grep -w EMAIL | cut -d '=' -f2 )
pbsprj=$( cat $runfile | grep -w PBSPROJECTID | cut -d '=' -f2 )
epilogue=$( cat $runfile | grep -w EPILOGUE | cut -d '=' -f2 )
input_type=$( cat $runfile | grep -w INPUTTYPE | cut -d '=' -f2 | tr '[a-z]' '[A-Z]' )
scriptdir=$( cat $runfile | grep -w SCRIPTDIR | cut -d '=' -f2 )
sampleinfo=$( cat $runfile | grep -w SAMPLEINFORMATION | cut -d '=' -f2 )
`umask u=rwx,g=rwx,o=`


set +x; echo -e "\n\n\n############ checking input type: WGS or WES\n" >&2; set -x

if [ $input_type == "GENOME" -o $input_type == "WHOLE_GENOME" -o $input_type == "WHOLEGENOME" -o $input_type == "WGS" ]
then
	pbscpu=$( cat $runfile | grep -w PBSCPUOTHERWGEN | cut -d '=' -f2 )
	pbsqueue=$( cat $runfile | grep -w PBSQUEUEWGEN | cut -d '=' -f2 )
elif [ $input_type == "EXOME" -o $input_type == "WHOLE_EXOME" -o $input_type == "WHOLEEXOME" -o $input_type == "WES" ]
then
	pbscpu=$( cat $runfile | grep -w PBSCPUOTHEREXOME | cut -d '=' -f2 )
	pbsqueue=$( cat $runfile | grep -w PBSQUEUEEXOME | cut -d '=' -f2 )
else
	MSG="Invalid value for parameter INPUTTYPE=$input_type  in configuration file."
	echo -e "Program $0 stopped.\n\n$MSG" | mail -s "[Task #${reportticket}]" "$redmine,$email"
	exit 1;
fi

set +x; echo -e "\n\n\n############ checking workflow scripts directory\n" >&2; set -x;

if [ ! -d $scriptdir ]
then
	MSG="SCRIPTDIR=$scriptdir directory not found"
	echo -e "Program $0 stopped.\n\nReason=$MSG" | mail -s "[Task #${reportticket}]" "$redmine,$email"
	exit 1;
fi

set +x; echo -e "\n\n\n############ checking sample configuration file\n" >&2; set -x;

if [ ! -s $sampleinfo ]
then
	MSG="SAMPLEINFORMATION=$sampleinfo sample configuration file not found"
	echo -e "Program $0 stopped.\n\nReason=$MSG" | mail -s "[Task #${reportticket}]" "$redmine,$email"
	exit 1;
fi
set +x; echo -e "\n\n\n############ checking email for receiving pipeline execution event\n" >&2; set -x;

if [ -z $email ]
then
	MSG="Invalid value for parameter PBSEMAIL=$email in configuration file"
	echo -e "Program $0 stopped.\n\n$MSG" | mail -s "[Task #${reportticket}]" "$redmine,$email"
	exit 1;
fi

set +x; echo -e "\n\n\n############ checking output directory\n" >&2; set -x;

if [ ! -d $outputdir ]
then
	mkdir -p $outputdir/logs
else 
	echo "resetting directory"
	`rm -r $outputdir/*`
	mkdir -p $outputdir/logs
fi
#`chmod -R 770 $outputdir/`
`chmod 740 $epilogue`

set +x; echo -e "\n\n\n############ copy configuration files to output directory\n" >&2; set -x;

`cp $runfile $outputdir/runfile.txt`
`cp $sampleinfo $outputdir/sampleinfo.txt`
runfile=$outputdir/runfile.txt


set +x; echo -e "\n ### initialize autodocumentation script ### \n"; set -x;
truncate -s 0 $outputdir/WorkflowAutodocumentationScript.sh
echo -e "#!/bin/bash \n" > $outputdir/WorkflowAutodocumentationScript.sh
WorkflowName=`basename $outputdir`  
echo "# @begin $WorkflowName" >> $outputdir/WorkflowAutodocumentationScript.sh


outputlogs=$outputdir/logs

set +x; echo -e "\n ### LAUNCH THE CONFIGURATION SCIPT. THIS JOBID WILL BECOME THE PIPELINE-ID FOR THIS RUN### \n"; set -x;

qsub1=$outputlogs/qsub.CONFIGURE
echo "#PBS -A $pbsprj" >> $qsub1
echo "#PBS -N CONFIGURE" >> $qsub1
echo "#PBS -l epilogue=$epilogue" >> $qsub1
echo "#PBS -l walltime=00:03:00" >> $qsub1
echo "#PBS -l nodes=1:ppn=1" >> $qsub1
echo "#PBS -o $outputlogs/log.CONFIGURE.ou" >> $qsub1
echo "#PBS -e $outputlogs/log.CONFIGURE.in" >> $qsub1
echo "#PBS -q $pbsqueue" >> $qsub1
echo "#PBS -m ae" >> $qsub1
echo "#PBS -M $email" >> $qsub1
echo "$scriptdir/configure.sh $runfile $outputlogs/log.CONFIGURE.in $outputlogs/log.CONFIGURE.ou $email $outputlogs/qsub.CONFIGURE " >> $qsub1
echo -e "\n\n" >> $qsub1
echo "exitcode=\$?" >> $qsub1
echo -e "if [ \$exitcode -ne 0 ]\nthen " >> $qsub1
echo "   echo -e \"\n\n configure.sh failed with exit code = \$exitcode \n runfile=$outputdir/runfile.txt\n\" | mail -s \"[Task #${reportticket}]\" \"$redmine,$email\"" >> $qsub1 
echo -e "\n\n   exit 1" >> $qsub1
echo "fi" >> $qsub1

#`chmod a+r $qsub1`               
jobid=`qsub $qsub1`
set +x; echo -e "\n ### jobid for configure.sh becomes pipeid. It will be stored in a couple of files ### \n"; set -x;
pipeid=$( echo $jobid | sed "s/\.[a-z]*[0-9]*//g" )
echo $pipeid >> $outputlogs/CONFIGUREpbs
echo $pipeid >> $outputlogs/pbs.CONFIGURE
echo `date`

##### the first part of the Report also needs to be stored in Summary.Report
truncate -s 0 $outputdir/logs/Summary.Report

MSG="Variant calling workflow with id:[${pipeid}] started by username:$USER at: "$( echo `date` )
LOGS="jobid=${jobid}\nqsubfile=$outputlogs/qsub.CONFIGURE\nrunfile=$outputdir/runfile.txt\nerrorlog=$outputlogs/log.CONFIGURE.in\noutputlog=$outputlogs/log.CONFIGURE.ou"
echo -e "$MSG\n\nDetails:\n\n$LOGS" | mail -s "[Task #${reportticket}]" "$redmine,$email"
echo -e "$MSG\n\nDetails:\n\n$LOGS" >> $outputdir/logs/Summary.Report

