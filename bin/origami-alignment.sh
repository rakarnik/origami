#!/bin/bash

BINDIR=~/dsday/origami/bin ### Need to generalize this
OUTPUTDIR=output
VERBOSE=off
SKIP=on
PARALLEL=off
SPLITNUM=4000000
BZPOSTFIX="[.]bz2$"
BOWTIEIDX=notafile

source $BINDIR/dispatch.sh

verbose() {
	if [ "$VERBOSE" = on ]
	then
		NOWTIME=$(date)
		echo "[$NOWTIME] $1"
	fi
}

dispatch() {
        if [ "$PARALLEL" = on ]
        then
                bsub -K -q normal -J origami -o $OUTPUTDIR/logs/cluster_log.txt "$@" &
        else
                eval "$@"
        fi
}

helpmenu() {
  if [ $# -eq 1 ];
  then
    echo $1
  fi
  echo "origami.sh [options] <bowtie index> <first FASTQ> <second FASTQ>"
  echo "  -o,--output= output directory (default output)"
  echo "  -h Help menu"
  echo "  -v verbose mode"
  echo "  -p parallel LSF mode (distributed bsub)"
  echo "  --splitnum=<NUM> Split reads into NUM for -p (default none)"
  echo "  --bowtieidx= Bowtie index (deprecated, inactive)"
}

TEMP=`getopt -o o::hvap -l output::,noskip,splitnum::,bowtieidx: -n 'origami' -- "$@"`
eval set -- "$TEMP"

while [ $# -ge 1 ]; do
	case "$1" in
		--)
			shift
			break
			;;
		-o|--output)
			OUTPUTDIR=$2
			shift
			;;
		-h)
			helpmenu
			exit 0
			;;
		-v)
			VERBOSE=on
			;;
		--noskip)
			SKIP=off
			;;
		-p)
			PARALLEL=on
			;;
		--splitnum)
		  SPLITNUM=$(expr "$2" \* 4)
		  shift
		  ;;
		--bowtieidx)
		  echo "Deprecated option (does not do anything)"
		  BOWTIEIDX=$2
		  shift
		  ;;
	esac
	shift
done

if [ $# -lt 3 ];
then
  helpmenu "Error: did not supply necessary file name arguments"
  exit 1
fi

BOWTIEIDX="$1"
LEFTREADS="$2"
RIGHTREADS="$3"

echo "Launching origami..."

verbose "Analyzing $LEFTREADS and $RIGHTREADS"

verbose "Creating output directory"
mkdir $OUTPUTDIR
verbose "Creating temporary file directory"
mkdir $OUTPUTDIR/tmp
verbose "Creating logs directory"
mkdir $OUTPUTDIR/logs

### handle zip status
#if [[ $LEFTREADS =~ $BZPOSTFIX ]]
#then
#	dispatch "bzcat $LEFTREADS > $OUTPUTDIR/tmp/left_unzip.fq"
#	LEFTREADS=$OUTPUTDIR/tmp/left_unzip.fq
#fi

#if [[ $RIGHTREADS =~ $BZPOSTFIX ]]
#then
#        dispatch "bzcat $RIGHTREADS > $OUTPUTDIR/tmp/right_unzip.fq"
#        RIGHTREADS=$OUTPUTDIR/tmp/right_unzip.fq
#fi

#wait

verbose "Removing adapter sequences on $LEFTREADS and $RIGHTREADS"
if [ "$SKIP" = off -o ! -e "$OUTPUTDIR/mapped_reads.bam" ]
then #&& $BINDIR/adapter_trim.sh $OUTPUTDIR $PARALLEL $SPLITNUM $LEFTREADS $RIGHTREADS

  ## structure of script influenced by Diego's work

  if [ $PARALLEL = "on" ]
  then
    # need to generalize this
    dispatch "bzcat $LEFTREADS | sed -e 's/\/[0-9];[0-9]//' > $OUTPUTDIR/tmp/left_reads.fq"
    dispatch "bzcat $RIGHTREADS | sed -e 's/\/[0-9];[0-9]//' > $OUTPUTDIR/tmp/right_reads.fq"
  
    wait 
    dispatch "split -l $SPLITNUM $OUTPUTDIR/tmp/left_reads.fq $OUTPUTDIR/tmp/leftreads"
    dispatch "split -l $SPLITNUM $OUTPUTDIR/tmp/right_reads.fq $OUTPUTDIR/tmp/rightreads"
  
    wait

  
    #rm $OUTPUTDIR/tmp/left_reads.fq $OUTPUTDIR/tmp/right_reads.fq
    dispatch "bzip2 $OUTPUTDIR/tmp/left_reads.fq"
    dispatch "bzip2 $OUTPUTDIR/tmp/right_reads.fq"

    wait
  
    ## One assumption here is that split names the files in the same linear order -- maybe this should be done differently?
    LEFTREADS=($(ls $OUTPUTDIR/tmp/leftreads*))
    RIGHTREADS=($(ls $OUTPUTDIR/tmp/rightreads*))
    for ((i=0;i<${#LEFTREADS[@]};++i)); do
      dispatch cutadapt -f fastq -n 3 -m 17 --overlap 10 -a forward="ACGCGATATCTTATCTGACT" -a reverse="AGTCAGATAAGATATCGCGT" -o $OUTPUTDIR/tmp/l_t1_$i.fq --untrimmed-output $OUTPUTDIR/tmp/l_nt1_$i.fq -p $OUTPUTDIR/tmp/r_t1_$i.fq --untrimmed-paired-output $OUTPUTDIR/tmp/r_nt1_$i.fq ${LEFTREADS[$i]} ${RIGHTREADS[$i]}
    done
    wait
  
    for ((i=0;i<${#LEFTREADS[@]};++i)); do
      dispatch cutadapt -n 3 -m 17 --overlap 10 -a forward="ACGCGATATCTTATCTGACT" -a reverse="AGTCAGATAAGATATCGCGT" -o $OUTPUTDIR/tmp/r_t2_$i.fq --untrimmed-output $OUTPUTDIR/tmp/r_nt2_$i.fq -p $OUTPUTDIR/tmp/l_t2_$i.fq --untrimmed-paired-output $OUTPUTDIR/tmp/l_nt2_$i.fq $OUTPUTDIR/tmp/r_nt1_$i.fq $OUTPUTDIR/tmp/l_nt1_$i.fq
      dispatch cutadapt -n 3 -m 17 --overlap 10 -a forward="ACGCGATATCTTATCTGACT" -a reverse="AGTCAGATAAGATATCGCGT" -o $OUTPUTDIR/tmp/r_t3_$i.fq --untrimmed-output $OUTPUTDIR/tmp/r_nt3_$i.fq -p $OUTPUTDIR/tmp/l_t3_$i.fq --untrimmed-paired-output $OUTPUTDIR/tmp/l_nt3_$i.fq $OUTPUTDIR/tmp/r_t1_$i.fq $OUTPUTDIR/tmp/l_t1_$i.fq
    done

    wait
  
    dispatch "cat $OUTPUTDIR/tmp/l_t3*.fq $OUTPUTDIR/tmp/l_nt3*.fq $OUTPUTDIR/tmp/l_t2*.fq > $OUTPUTDIR/tmp/left_kept.fq"
    dispatch "cat $OUTPUTDIR/tmp/r_t3*.fq $OUTPUTDIR/tmp/r_nt3*.fq $OUTPUTDIR/tmp/r_t2*.fq > $OUTPUTDIR/tmp/right_kept.fq"

    dispatch "cat $OUTPUTDIR/tmp/l_nt2*.fq > $OUTPUTDIR/tmp/left_untrimmed.fq"
    dispatch "cat $OUTPUTDIR/tmp/r_nt2*.fq > $OUTPUTDIR/tmp/right_untrimmed.fq"

    wait
  
    rm $OUTPUTDIR/tmp/leftreads* $OUTPUTDIR/tmp/rightreads*

  else

    dispatch "sed -e 's/\/[0-9];[0-9]//' $LEFTREADS > $OUTPUTDIR/tmp/left_reads.fq"
    dispatch "sed -e 's/\/[0-9];[0-9]//' $RIGHTREADS > $OUTPUTDIR/tmp/right_reads.fq"

    wait

    dispatch cutadapt -n 3 -m 17 --overlap 10 -a forward="ACGCGATATCTTATCTGACT" -a reverse="AGTCAGATAAGATATCGCGT" -o $OUTPUTDIR/tmp/l_t1.fq --untrimmed-output $OUTPUTDIR/tmp/l_nt1.fq -p $OUTPUTDIR/tmp/r_t1.fq --untrimmed-paired-output $OUTPUTDIR/tmp/r_nt1.fq $OUTPUTDIR/tmp/left_reads.fq $OUTPUTDIR/tmp/right_reads.fq
    wait
    dispatch cutadapt -n 3 -m 17 --overlap 10 -a forward="ACGCGATATCTTATCTGACT" -a reverse="AGTCAGATAAGATATCGCGT" -o $OUTPUTDIR/tmp/r_t2.fq --untrimmed-output $OUTPUTDIR/tmp/r_nt2.fq -p $OUTPUTDIR/tmp/l_t2.fq --untrimmed-paired-output $OUTPUTDIR/tmp/l_nt2.fq $OUTPUTDIR/tmp/r_nt1.fq $OUTPUTDIR/tmp/l_nt1.fq
    dispatch cutadapt -n 3 -m 17 --overlap 10 -a forward="ACGCGATATCTTATCTGACT" -a reverse="AGTCAGATAAGATATCGCGT" -o $OUTPUTDIR/tmp/r_t3.fq --untrimmed-output $OUTPUTDIR/tmp/r_nt3.fq -p $OUTPUTDIR/tmp/l_t3.fq --untrimmed-paired-output $OUTPUTDIR/tmp/l_nt3.fq $OUTPUTDIR/tmp/r_t1.fq $OUTPUTDIR/tmp/l_t1.fq

    wait

    dispatch "cat $OUTPUTDIR/tmp/l_t3.fq $OUTPUTDIR/tmp/l_nt3.fq $OUTPUTDIR/tmp/l_t2.fq > $OUTPUTDIR/tmp/left_kept.fq"
    dispatch "cat $OUTPUTDIR/tmp/r_t3.fq $OUTPUTDIR/tmp/r_nt3.fq $OUTPUTDIR/tmp/r_t2.fq > $OUTPUTDIR/tmp/right_kept.fq"

    dispatch "cat $OUTPUTDIR/tmp/l_nt2.fq > $OUTPUTDIR/tmp/left_untrimmed.fq"
    dispatch "cat $OUTPUTDIR/tmp/r_nt2.fq > $OUTPUTDIR/tmp/right_untrimmed.fq"

    wait
  
    rm $OUTPUTDIR/tmp/left_reads.fq $OUTPUTDIR/tmp/right_reads.fq
  
  fi

  ### Cleanup
  rm $OUTPUTDIR/tmp/l_*.fq $OUTPUTDIR/tmp/r_*.fq

  dispatch bzip2 $OUTPUTDIR/tmp/left_untrimmed.fq
  dispatch bzip2 $OUTPUTDIR/tmp/right_untrimmed.fq

  wait

  #rm -f $OUTPUTDIR/tmp/left_untrimmed.fq $OUTPUTDIR/tmp/right_untrimmed.fq
fi


rm -f $OUTPUTDIR/tmp/left_unzip.fq  $OUTPUTDIR/tmp/right_unzip.fq

verbose "Aligning reads"
if [ "$SKIP" = off -o ! -e "$OUTPUTDIR/mapped_reads.bam" ] #&& $BINDIR/bowtie_align.sh $OUTPUTDIR $BOWTIEIDX $PARALLEL $SPLITNUM
then
  if [ $PARALLEL = "on" ]
  then
    dispatch "split -l $SPLITNUM $OUTPUTDIR/tmp/left_kept.fq $OUTPUTDIR/tmp/leftkept"
    dispatch "split -l $SPLITNUM $OUTPUTDIR/tmp/right_kept.fq $OUTPUTDIR/tmp/rightkept"

    wait

    for FILE in $OUTPUTDIR/tmp/leftkept*
    do
  	  dispatch "bowtie -n 1 -m 1 -p 6 --sam $BOWTIEIDX $FILE > $FILE.sam; samtools view -Sb $FILE.sam > $FILE.bam; rm $FILE.sam"
    done

    for FILE in $OUTPUTDIR/tmp/rightkept*
    do
    	dispatch "bowtie -n 1 -m 1 -p 6 --sam $BOWTIEIDX $FILE > $FILE.sam; samtools view -Sb $FILE.sam > $FILE.bam; rm $FILE.sam"
    done

    wait

    dispatch "cd $OUTPUTDIR/tmp && samtools merge left_kept.bam leftkept*.bam"
    dispatch "cd $OUTPUTDIR/tmp && samtools merge right_kept.bam rightkept*.bam"

    wait

    dispatch "rm $OUTPUTDIR/tmp/leftkept* $OUTPUTDIR/tmp/rightkept*"
    wait
  else
    dispatch "bowtie -n 1 -m 1 -p 6 --sam $BOWTIEIDX $OUTPUTDIR/tmp/left_kept.fq > $OUTPUTDIR/tmp/left_kept.sam; samtools view -Sb $OUTPUTDIR/tmp/left_kept.sam > $OUTPUTDIR/tmp/left_kept.bam; rm $OUTPUTDIR/tmp/left_kept.sam"
    dispatch "bowtie -n 1 -m 1 -p 6 --sam $BOWTIEIDX $OUTPUTDIR/tmp/right_kept.fq > $OUTPUTDIR/tmp/right_kept.sam; samtools view -Sb $OUTPUTDIR/tmp/right_kept.sam > $OUTPUTDIR/tmp/right_kept.bam; rm $OUTPUTDIR/tmp/right_kept.sam"

    wait
  fi

  dispatch "samtools sort -Obam -Tlefttmp -n $OUTPUTDIR/tmp/left_kept.bam > $OUTPUTDIR/tmp/left_kept.sorted.bam"
  dispatch "samtools sort -Obam -Trighttmp -n $OUTPUTDIR/tmp/right_kept.bam > $OUTPUTDIR/tmp/right_kept.sorted.bam"

  wait

  dispatch "~/dsday/origami/bin/mapped-reads-merge $OUTPUTDIR/tmp/left_kept.sorted.bam $OUTPUTDIR/tmp/right_kept.sorted.bam $OUTPUTDIR/mapped_reads.bam"

  wait

  #dispatch "samtools sort -Obam -Ttmp $OUTPUTDIR/tmp/mapped_reads.bam > $OUTPUTDIR/mapped_reads.bam"

  #wait

  rm $OUTPUTDIR/tmp/left_kept.sorted.bam $OUTPUTDIR/tmp/right_kept.sorted.bam
  #rm $OUTPUTDIR/tmp/mapped_reads.bam

  #mv $OUTPUTDIR/tmp/left_kept.bam $OUTPUTDIR/left_kept.bam
  #mv $OUTPUTDIR/tmp/right_kept.bam $OUTPUTDIR/right_kept.bam
fi

wait #finish all remaining processes

echo "Calling peaks"
$BINDIR/peak-calling.sh $OUTPUTDIR

#echo "Finding links"

#bedtools pairtobed -bedpe -type both -a $OUTPUTDIR/mapped_reads.bam -b $OUTPUTDIR/peaks_peaks.narrowPeak > $OUTPUTDIR/raw-links.out

echo "Done"
