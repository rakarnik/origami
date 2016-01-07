source("~/scripts/tags.r")
source("~/scripts/peaks.r")

if(!interactive()) {
  args <- commandArgs(T)
  bamfile <- args[1]
  peakfile <- args[2]
}

pets <- readInBamFile(bamfile)
peaks <- read.narrow.peak.file(peakfile)

both.mapped <- !is.na(pets@pos) & !is.na(pets@mpos)

idx <- seq(1,sum(both.mapped),by=2)

first <- GRanges(seqnames=pets@rname[both.mapped][idx],
                 ranges=IRanges(pets@pos[both.mapped][idx],width=1),
                 strand='*')
second <- GRanges(seqnames=pets@rname[both.mapped][idx+1],
                  ranges=IRanges(pets@pos[both.mapped][idx+1],width=1),
                  strand='*')

of <- findOverlaps(first,peaks)
os <- findOverlaps(second,peaks)

total <- table(c(subjectHits(of),subjectHits(os)))
p <- peaks
mcols(p)[,"counts"] <- rep(0,length(p))
mcols(p)[,"counts"][as.integer(names(total))] <- as.vector(total)

write.table(as.data.frame(p)[,c(1,2,3,12)],file='peak-counts.txt',sep='\t',col.names = F,row.names = F,quote=F)

l <- list()
qof <- queryHits(of)
sof <- subjectHits(of)
qos <- queryHits(os)
sos <- subjectHits(os)

midx <- match(qof,qos)
m <- matrix(c(sof[!is.na(midx)],sos[midx[!is.na(midx)]]),ncol=2)
m <- m[order(m[,1],m[,2]),]

f <- factor(paste(m[,1],m[,2],sep='_'))

intcounts <- do.call(rbind,lapply(split(1:nrow(m),f),function(idx) {
  if(length(idx) == 1 ) {
    ret <- c(m[idx,],1)
  } else {
    ret <- c(m[idx[1],],length(idx))
  }
  
  ret
}))

rownames(intcounts) <- NULL

outtable <- as.data.frame(peaks)[,c(1,2,3)]
outtable <- cbind(outtable[intcounts[,1],],outtable[intcounts[,2],],intcounts[,3])
write.table(outtable,file="int-counts.txt",sep='\t',col.names=F,row.names=F,quote=F)