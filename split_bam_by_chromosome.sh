#!/bin/bash
redmine=hpcbio-redmine@igb.illinois.edu
if [ $# -gt 16 ]
then
	MSG="parameter mismatch."
        echo -e "program=$0 stopped. Reason=$MSG" | mail -s 'Variant Calling Workflow failure message' "$redmine"
        exit 1;
else
    set -x
    echo `date`
    umask 0027
    scriptfile=$0
    runfile=$1
    picardir=$2
    samdir=$3
    outputdir=$5
    bamfile=$6
    infile=$7
    outfile=$8
    rgparms=$9
    flag=${10}
    chr=${11}
    elog=${12}
    olog=${13}
    email=${14}
    qsubfile=${15}
    RealignOutputLogs=${16}
    LOGS="jobid:${PBS_JOBID}\nqsubfile=$qsubfile\nerrorlog=$elog\noutputlog=$olog"

    set +x; echo -e "\n\n#############      cheching parameters  ###############\n\n" >&2; set -x;

    memprof=$( cat $runfile | grep -w MEMPROFCOMMAND | cut -d '=' -f2 )
    javadir=$( cat $runfile | grep -w JAVADIR | cut -d '=' -f2 )


    if [ ! -d $outputdir ]
    then
       MSG="$outputdir realign directory not found"
       echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
       #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
       exit 1;
    fi
    if [ ! -d $picardir ]
    then
       MSG="$picardir picard directory not found"
       echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
       #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
       exit 1;
    fi
    if [ ! -d $samdir ]
    then
       MSG="$picardir samtools directory not found"
       echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
       #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
       exit 1;
    fi

    if [ -z $javadir ]
    then
	MSG="A value must be specified for JAVADIR in configuration file"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	exit 1;
    #else
        #`/usr/local/modules-3.2.9.iforge/Modules/bin/modulecmd bash load $javamodule`
    #        `module load $javamodule`
    fi          
    if [ ! -s $bamfile ]
    then
	MSG="$bamfile bam file to be sorted was not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	exit 1;
    fi


    set +x; echo -e "\n\n#############     parameters  ok ###############\n\n" >&2; set -x;

    set +x; echo -e "\n\n#############     next, split $infile by chr $chr ###############\n\n" >&2; set -x;

    cd $outputdir
    echo `date`
    if [ ! -s $infile ]
    then
        $memprof $samdir/samtools view -b $bamfile $chr > $infile
        exitcode=$?
        if [ $exitcode -ne 0 ]
        then
	    MSG="samtools view command failed exitcode=$exitcode. $infile bam file to be sorted within region:[$chr] was not created"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
        fi
        if [ ! -s $infile ]
        then
	    MSG="$infile bam file to be sorted within region:[$chr] was not created"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        fi
	echo `date`
        $memprof $samdir/samtools index $infile
        exitcode=$?
        if [ $exitcode -ne 0 ]
        then
	    MSG="samtools index command failed exitcode=$exitcode. $infile bam file to be sorted within region:[$chr] was not created"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
        fi
	echo `date`
    fi

    tmpfile=tmp.wrg.$infile
    parameters=$( echo $rgparms | tr ":" " " )
    sortflag=$( echo $flag | tr '[a-z]' '[A-Z]' )




    set +x; echo -e "\n ## before sorting, we need to make sure the bam file has readgroup info\n" >&2; set -x

    if [ $sortflag == "NCSA" ]
    then
       set +x; echo -e "\n ## alignment was done inhouse. we need to add_readgroup info" >&2; set -x
       $memprof $javadir/java -Xmx1024m -Xms1024m -jar $picardir/AddOrReplaceReadGroups.jar \
	   INPUT=$infile \
	   OUTPUT=$tmpfile \
	   MAX_RECORDS_IN_RAM=null \
	   TMP_DIR=$outputdir \
	   SORT_ORDER=unsorted \
           $parameters \
	   VALIDATION_STRINGENCY=SILENT

       exitcode=$?
       if [ $exitcode -ne 0 ]
       then
	    MSG="addorreplacereadgroup command failed exitcode=$exitcode  split_bam_by_chromosome failed "
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
       fi
       echo `date`
    else
	set +x; echo -e "\n ## alignment was done at an external facility. checking if readgroup info is present" >&2; set -x
	$memprof $samdir/samtools view -H $infile > $infile.header
        exitcode=$?
        if [ $exitcode -ne 0 ]
        then
	    MSG="samtools view command failed exitcode=$exitcode  split_bam_by_chromosome failed "
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
        fi
	echo `date`
	match=$( cat $file.header | grep '^@RG' )
	lenmatch=`expr ${#match}`
	if [ $lenmatch -gt 0 ]
	then
            set +x; echo -e "\n ## readgroup info found in input file." >&2; set -x
            cp $infile $tmpfile
	else
            set +x; echo -e "\n ## readgroup info NOT found in input file. Adding it now..." >&2; set -x
	    $memprof $javadir/java -Xmx1024m -Xms1024m -jar $picardir/AddOrReplaceReadGroups.jar \
		   INPUT=$infile \
		   OUTPUT=$tmpfile \
		   MAX_RECORDS_IN_RAM=null \
		   TMP_DIR=$outputdir \
		   SORT_ORDER=unsorted \
		   $parameters \
		   VALIDATION_STRINGENCY=SILENT
            exitcode=$?
            if [ $exitcode -ne 0 ]
            then
		MSG="addorreplacereadgroup command failed exitcode=$exitcode  split_bam_by_chromosome failed "
		echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		exit $exitcode;
            fi
	    echo `date`

	fi
    fi

    if [ ! -s $tmpfile ]
    then
	MSG="$tmpfile bam file not created. add_readGroup step failed. split_bam_by_chromosome failed "
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	exit 1;
    fi
    echo `date`


    set +x; echo -e "\n\n#############     next, sortsam ###############\n\n" >&2; set -x;

    $memprof $javadir/java -Xmx1024m -Xms1024m -jar $picardir/SortSam.jar \
	INPUT=$tmpfile \
	OUTPUT=$outfile \
	TMP_DIR=$outputdir \
	SORT_ORDER=coordinate \
	MAX_RECORDS_IN_RAM=null \
	CREATE_INDEX=true \
	VALIDATION_STRINGENCY=SILENT

    exitcode=$?
    if [ $exitcode -ne 0 ]
    then
	MSG="sortsam command failed exitcode=$exitcode  split_bam_by_chromosome failed "
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	exit $exitcode;
    fi
    echo `date`

    if [ ! -s $outfile ]
    then
	MSG="$outfile sort bam file not created.  split_bam_by_chromosome failed "
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	exit 1;
    fi
    $memprof $samdir/samtools index $outfile
    exitcode=$?
    if [ $exitcode -ne 0 ]
    then
	MSG="samtools index command failed exitcode=$exitcode  split_bam_by_chromosome failed "
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	exit $exitcode;
    fi
    echo `date`
    $memprof $samdir/samtools view -H $outfile > $outfile.header
    exitcode=$?
    if [ $exitcode -ne 0 ]
    then
	MSG="samtools viewcommand failed exitcode=$exitcode  split_bam_by_chromosome failed "
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	#echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	exit $exitcode;
    fi
    echo `date`
fi
