#!/bin/bash
# written in collaboration with Mayo Bioinformatics core group
#
# script to combine chr GVCFs for a sample into a single file, convert GVCF to VCF, add missing tags and copy to delivery folder
# 
#########################################################################################################
#redmine=hpcbio-redmine@igb.illinois.edu
redmine=grendon@illinois.edu

set -x
echo `date`
umask 0027
scriptfile=$0
realignedbam=$1
gvcfFile=$2
plainVcfFile=$3
outputdir=$5
runfile=$6
failedlog=$7
email=$8
qsubfile=$9

LOGS="jobid:${PBS_JOBID}\nqsubfile=$qsubfile\nerrorlog=$failedlog\noutputlog=$failedlog"

set +x; echo -e "\n\n" >&2; 
echo -e "####################################################################################################" >&2
echo -e "#####################################                       ########################################" >&2
echo -e "##################################### PARSING RUN INFO FILE ########################################" >&2
echo -e "##################################### AND SANITY CHECK      ########################################" >&2
echo -e "####################################################################################################" >&2
echo -e "\n\n" >&2; set -x;

rootdir=$( cat $runfile | grep -w OUTPUTDIR | cut -d '=' -f2 )
input_type=$( cat $runfile | grep -w INPUTTYPE | cut -d '=' -f2 | tr '[a-z]' '[A-Z]' )
javadir=$( cat $runfile | grep -w JAVADIR | cut -d '=' -f2 )
gatk=$( cat $runfile | grep -w GATKDIR | cut -d '=' -f2 )
snvcaller=$( cat $runfile | grep -w SNV_CALLER | cut -d '=' -f2 )
samdir=$( cat $runfile | grep -w SAMDIR | cut -d '=' -f2 )
javadir=$( cat $runfile | grep -w JAVADIR | cut -d '=' -f2 )
samdir=$( cat $runfile | grep -w SAMDIR | cut -d '=' -f2 )
novodir=$( cat $runfile | grep -w NOVODIR | cut -d '=' -f2 )
refdir=$( cat $runfile | grep -w REFGENOMEDIR | cut -d '=' -f2 )
ref=$( cat $runfile | grep -w REFGENOME | cut -d '=' -f2 )
dbsnp=$( cat $runfile | grep -w DBSNP | cut -d '=' -f2 )
deliveryfolder=$( cat $runfile | grep -w DELIVERYFOLDER | cut -d '=' -f2 )
indices=$( cat $runfile | grep -w CHRINDEX | cut -d '=' -f2 | tr ':' ' ' )
thr=$( cat $runfile | grep -w PBSTHREADS | cut -d '=' -f2 )
variantcmd=$( cat $runfile | grep -w VARIANT_CMD | cut -d '=' -f2 | tr '[a-z]' '[A-Z]' )
variantAnalysis=$( cat $runfile | grep -w VARIANT_ANALYSIS | cut -d '=' -f2 | tr '[a-z]' '[A-Z]' )
gvcf2vcf=$( cat $runfile | grep -w CONVERT_GVCF2VCF | cut -d '=' -f2 | tr '[a-z]' '[A-Z]' )
tabixdir=$( cat $runfile | grep -w TABIXDIR | cut -d '=' -f2 )

qc_result=$rootdir/QC_Results.txt
 
set +x; echo -e "\n\n########### checking tool directories     #############\n\n" >&2; set -x;

if [ ! -d $samdir ]
then
	MSG="$samdir samtools directory not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi

if [ ! -d $gatk ]
then
	MSG="$gatk GATK directory not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi

if [ ! -d $tabixdir ]
then
	MSG="$tabixdir tabix directory not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi

set +x; echo -e "\n\n########### checking callsets     #############\n\n" >&2; set -x;

if [ ! -d $refdir ]
then
	MSG="$refdir reference genome directory not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi
     
if [ ! -s $refdir/$ref ]
then
	MSG="$ref reference genome not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi

if [ ! -s $refdir/$dbsnp ]
then
	MSG="$refdir/$dbsnp dbSNP for reference genome not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog 
	exit 1;
fi

set +x; echo -e "\n\n########### checking inout/output folder     #############\n\n" >&2; set -x;

if [ ! -d $outputdir ]
then
	MSG="$outputdir vcall directory not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi

if [ ! -s $realignedbam ]
then
	MSG="$realignedbam realigned.bam file not found"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi


set +x; echo -e "\n\n########### checking delivery folder     #############\n\n" >&2; set -x;

if [ `expr ${#deliveryfolder}` -lt 2 ]
then
    deliverydir=$rootdir/delivery/Vcfs
else
    deliverydir=$rootdir/$deliveryfolder/Vcfs
fi

if [ ! -d $deliverydir ]
then
    `mkdir -p $deliverydir`
fi


set +x; echo -e "\n\n########### checking GVCF 2 VCF conversion     #############\n\n" >&2; set -x;

if [ `expr ${#gvcf2vcf}` -lt 1 ]
then
	gvcf2vcf="NO"
fi
if [ $gvcf2vcf == "1" ]
then
	gvcf2vcf="YES"
fi
if [ $gvcf2vcf == "0" ]
then
	gvcf2vcf="NO"
fi  

#tabix needs to be on your path for GATK to produce *tbi files
export PATH=${PATH}:$tabixdir

set +x; echo -e "\n\n" >&2;
echo "#################################################################################" >&2
echo "################  PREPARATORY WORK                           ###################" >&2
echo "#################################################################################" >&2
echo -e "\n\n" >&2; set -x;

cd $outputdir/..
sample=`basename $PWD`
cd $outputdir
inputFilename=$sample
rawGVCF=${inputFilename}.combined.raw.g.vcf
verifiedOut=${inputFilename}.verifyOutput        # output prefix for verifybam command



set +x; echo -e "\n\n" >&2;
echo "#################################################################################" >&2
echo "################  STEP1: form an ordered list of the vcf files that will be merged" >&2
echo "#################################################################################" >&2
echo -e "\n\n" >&2; set -x;

cd $outputdir

ordered_vcfs=""

for chr in $indices
do

	set +x; echo -e "\n\n########### processing $sample $chr     #############\n\n" >&2; set -x;

	if [ -s ${sample}.$chr.raw.g.vcf ]
	then
		### the vcf file for this chr and  GATK-CombineGVCFs

		thisvcf="  --variant  "${sample}.$chr.raw.g.vcf

		### now we append this name to the ordered list

		ordered_vcfs=${ordered_vcfs}$thisvcf
	fi
done

set +x; echo -e "\n\n########### check that we have a non-empty list     #############\n\n" >&2; set -x;

if [ `expr ${#ordered_vcfs}` -lt 1 ]
then
	MSG="no GVCF files to merge for $sample in folder $outputdir"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi

set +x; echo -e "\n\n" >&2;
echo -e "##################################################################################"  >&2
echo -e "########### STEP2: merge with GATK-CombineGVCFs                              #####" >&2
echo -e "##################################################################################" >&2
echo -e "\n\n" >&2; set -x;

java -Xmx8g  -Djava.io.tmpdir=$outputdir -jar $gatk/GenomeAnalysisTK.jar \
	 -R $refdir/$ref \
	 --dbsnp $refdir/$dbsnp \
	 $ordered_vcfs  \
	 -T CombineGVCFs \
	 -o $gvcfFile

exitcode=$?
echo `date`
if [ $exitcode -ne 0 ]
then
	MSG="GATK CombineGVCFs  command failed exitcode=$exitcode. sample $sample"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit $exitcode;
fi

if [ ! -s $gvcfFile ]
then
	MSG="GATK CombineGVCFs did not generate output file exitcode=$exitcode. sample $sample"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi 

set +x; echo -e "\n\n" >&2;
echo -e "##################################################################################"  >&2
echo -e "########### STEP3: copy file to delivery folder                              #####" >&2
echo -e "##################################################################################" >&2
echo -e "\n\n" >&2; set -x;

echo `date`

cp $gvcfFile $deliverydir

echo `date`

set +x; echo -e "\n\n" >&2;
echo -e "##################################################################################"  >&2
echo -e "########### STEP4: convert GVCF to PLAIN    VCF                              #####" >&2
echo -e "##################################################################################" >&2
echo -e "\n\n" >&2; set -x;

if [ $gvcf2vcf == "NO" ]
then

	set +x; echo -e "\n\n" >&2;
	echo -e "##################################################################################"  >&2
	echo -e "########### DONE. Exiting now                                                #####" >&2
	echo -e "##################################################################################" >&2
	echo -e "\n\n" >&2; set -x;

	exit 0;
fi

set +x; echo -e "\n\n########### variables      #############\n\n" >&2; set -x;

plainTmpVcf=tmp_${sample}.regular.raw.vcf


set +x; echo -e "\n\n########### run GenotypeGVCFs to convert GVCF to VCF     #############\n\n" >&2; set -x;

java -Xmx50g  -Djava.io.tmpdir=$outputdir -jar $gatk/GenomeAnalysisTK.jar \
	 -R $refdir/$ref \
	 --dbsnp $refdir/$dbsnp \
         -T GenotypeGVCFs \
         -o $plainTmpVcf \
         -nt $thr \
         --variant $gvcfFile



exitcode=$?
echo `date`
if [ $exitcode -ne 0 ]
then
	MSG="GATK GenotypeGVCFs  command failed exitcode=$exitcode. sample $sample"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit $exitcode;
fi

if [ ! -s $plainTmpVcf ]
then
	MSG="GATK GenotypeGVCFs did not generate file exitcode=$exitcode. sample $sample"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi 

set +x; echo -e "\n\n########### run VariantAnnotator to add missing tags that UnifiedGenotyper always includes  #############\n\n" >&2; set -x;


java -Xmx50g  -Djava.io.tmpdir=$outputdir -jar $gatk/GenomeAnalysisTK.jar \
	 -R $refdir/$ref \
	 --dbsnp $refdir/$dbsnp \
	 -T VariantAnnotator \
	 -I $realignedbam \
         -V $plainTmpVcf \
         --disable_auto_index_creation_and_locking_when_reading_rods \
         -A VariantType \
         -A AlleleBalance -A BaseCounts -A BaseQualityRankSumTest -A ChromosomeCounts \
         -A Coverage -A FisherStrand -A GCContent -A HaplotypeScore \
         -A HomopolymerRun -A InbreedingCoeff -A LowMQ -A MappingQualityRankSumTest \
         -A MappingQualityZero -A NBaseCount -A QualByDepth -A RMSMappingQuality \
         -A ReadPosRankSumTest -A SpanningDeletions -A TandemRepeatAnnotator \
         -nt $thr \
         -o $plainVcfFile 

exitcode=$?
echo `date`
if [ $exitcode -ne 0 ]
then
	MSG="GATK VariantAnnotator  command failed exitcode=$exitcode. sample $sample"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit $exitcode;
fi

if [ ! -s $plainVcfFile ]
then
	MSG="GATK VariantAnnotator did not generate file exitcode=$exitcode. sample $sample"
	echo -e "program=$scriptfile stopped at line=$LINENO.\nReason=$MSG\n$LOGS" >> $failedlog
	exit 1;
fi 

set +x; echo -e "\n\n########### copy file to delivery folder  #############\n\n" >&2; set -x;

echo `date`

cp $plainVcfFile $deliverydir

echo `date`


set +x; echo -e "\n\n" >&2;
echo -e "##################################################################################"  >&2
echo -e "########### DONE. Exiting now                                                #####" >&2
echo -e "##################################################################################" >&2
echo -e "\n\n" >&2; set -x;
