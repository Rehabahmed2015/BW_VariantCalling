#!/bin/bash
#	
#  script to realign and recalibrate the aligned file(s) 
########################################################
redmine=hpcbio-redmine@igb.illinois.edu
set -x
if [ $# != 11 ];
then
	MSG="parameter mismatch."
        echo -e "program=$0 stopped. Reason=$MSG" | mail -s 'Variant Calling Workflow failure message' "$redmine"
        exit 1;
else					

	echo `date`
        umask 0027
	scriptfile=$0
        realigndir=$1
        outputfile=$2	
        chr=$3
        infile=$4
        realparms=$5
        sample=$6
        runfile=$7
	elog=$8
	olog=$9
	email=${10}
        qsubfile=${11}
	LOGS="jobid:${PBS_JOBID}\nqsubfile=$qsubfile\nerrorlog=$elog\noutputlog=$olog"

        if [ ! -s $runfile ]
        then
	    MSG="$runfile configuration file not found"
	   echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	   #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        fi


        set +x; echo -e "\n\n############# CHECKING PARAMETERS ###############\n\n" >&2; set -x;
        
        javadir=$( cat $runfile | grep -w JAVADIR | cut -d '=' -f2 )
        threads=$( cat $runfile | grep -w PBSTHREADS | cut -d '=' -f2 )
        refdir=$( cat $runfile | grep -w REFGENOMEDIR | cut -d '=' -f2 )
        ref=$( cat $runfile | grep -w REFGENOME | cut -d '=' -f2 )
        picardir=$( cat $runfile | grep -w PICARDIR | cut -d '=' -f2 )
        samdir=$( cat $runfile | grep -w SAMDIR | cut -d '=' -f2 )
        gatk=$( cat $runfile | grep -w GATKDIR | cut -d '=' -f2 )
        realignparams=$( cat $runfile | grep -w REALIGNPARMS | cut -d '=' -f2 )
	outputrootdir=$( cat $runfile | grep -w OUTPUTDIR | cut -d '=' -f2 )
        memprof=$( cat $runfile | grep -w MEMPROFCOMMAND | cut -d '=' -f2 )
        thr=`expr $threads "-" 1`
        #thr=`expr $threads "/" 2`

        real2parms=$( echo $realparms | tr ":" " " | sed "s/known /-known /g" )
        realparms=$( echo $realparms | tr ":" " " | sed "s/known /--known /g" )
        if [ ! -d $picardir ]
        then
	    MSG="$picardir picard directory not found"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""	    
           exit 1;
        fi
        if [ ! -d $samdir ]
        then
	    MSG="$samdir samtools directory not found"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        fi
        if [ ! -d $gatk ]
        then
	    MSG="$gatk GATK directory not found"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        fi

        if [ -z $javadir ]
        then
	    MSG="Value for JAVADIR must be specified in configuration file"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        #else
            #`/usr/local/modules-3.2.9.iforge/Modules/bin/modulecmd bash load $javamodule`
        #    `module load $javamodule`
        fi

        if [ ! -d $refdir ]
        then
	    MSG="$refdir reference genome directory not found"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        fi      
        if [ ! -s $refdir/$ref ]
        then
	    MSG="$ref reference genome not found"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        fi
        if [ ! -s $infile ]
        then
	    MSG="$infile sample file to split not found"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit 1;
        fi

        set +x; echo -e "\n\n" >&2; 
        echo "#################################################################################" >&2
        echo "################## STEP1: splitting sample=$sample by chr=$chr...################" >&2
        echo "#################################################################################" >&2
        echo -e "\n\n" >&2; set -x;
        
        cd $realigndir

        tmpfile=`basename $infile`
        $samdir/samtools view -bu -@ $thr $infile $chr > ${chr}.$tmpfile
	exitcode=$?
	echo `date`

	if [ $exitcode -ne 0 ]
	then
	    MSG="split by chr, samtools command failed exitcode=$exitcode. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
	fi
	
	if [ ! -s ${chr}.$tmpfile ]
	then
	    MSG="${chr}.$tmpfile bam file not created for chr $chr1. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
            exit 1;
	fi
        $samdir/samtools index ${chr}.$tmpfile
        $samdir/samtools view -H -@ $thr $tmpfile $chr > ${chr}.$tmpfile.header

	echo `date`
	
        set +x; echo -e "\n\n" >&2;
        echo "#################################################################################" >&2
        echo "################## STEP2: realign SAMPLE $sample on chr=$chr  ###################" >&2
        echo "#################################################################################" >&2
        echo -e "\n\n" >&2; set -x;
        
        echo "GATK is creating a target list...."
        $javadir/java -Xmx8g -Xms1024m -Djava.io.tmpdir=$realigndir -jar $gatk/GenomeAnalysisTK.jar \
	    -R $refdir/$ref \
	    -I $chr.$tmpfile \
	    -T RealignerTargetCreator \
            -nt $thr \
	    -o $chr.${tmpfile}.list $realparms

	exitcode=$?
	echo `date`

	if [ $exitcode -ne 0 ]
	then
	    MSG="realignertargetcreator command failed exitcode=$exitcode. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
	fi
	
	if [ ! -s ${chr}.${tmpfile}.list ]
	then
	    MSG="${chr}.${tmpfile}.list realignertargetcreator file not created. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
            exit 1;
	fi
	echo `date`

        echo "executing GATK IndelRealigner command and generating $outputfile"
	$javadir/java -Xmx8g -Xms1024m -Djava.io.tmpdir=$realigndir -jar $gatk/GenomeAnalysisTK.jar \
	    -R $refdir/$ref \
	    -I $chr.$tmpfile \
	    -T IndelRealigner \
            -L $chr \
	    -o ${chr}.${tmpfile}.realigned.bam \
	    -targetIntervals ${chr}.${tmpfile}.list $realignparams $real2parms

	exitcode=$?
	echo `date`
	if [ $exitcode -ne 0 ]
	then
	    MSG="indelrealigner command failed exitcode=$exitcode. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
	fi
	if [ ! -s ${chr}.${tmpfile}.realigned.bam ]
	then
	    MSG="${chr}.${tmpfile}.realigned.bam  indelrealigner file not created. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
            exit 1;
        fi	

        set +x; echo -e "\n\n" >&2;
        echo "#################################################################################" >&2
        echo "################## STEP3: samtools calmd                      ###################" >&2
        echo "#################################################################################" >&2
        echo -e "\n\n" >&2; set -x;
        
        $samdir/samtools calmd -Erbu ${chr}.${tmpfile}.realigned.bam $refdir/$ref > $outputfile
	exitcode=$?
	echo `date`
	if [ $exitcode -ne 0 ]
	then
	    MSG="samtools calmd command failed exitcode=$exitcode. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
	fi
	if [ ! -s $outputfile ]
	then
	    MSG="$outputfile output file not created. realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
            exit 1;
        fi

        set +x; echo -e "\n\n#############generating stats for $outputfile before exiting###############\n\n" >&2; set -x;

        $samdir/samtools index $outputfile
        $samdir/samtools view -H  $outputfile > ${outputfile}.header
        $samdir/samtools flagstat $outputfile > ${outputfile}.flagstat


	exitcode=$?
	echo `date`
	if [ $exitcode -ne 0 ]
	then
	    MSG="samtools flagstat command failed exitcode=$exitcode  realignment for sample $sample stopped"
	    echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" #| ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
		    #echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" | ssh iforge "mailx -s '[Support #200] variant identification pipeline' "$redmine,$email""
	    exit $exitcode;
	fi
        echo "done $outputfile was created. exiting now"

fi
