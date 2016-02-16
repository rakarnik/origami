library(GenomicRanges,quietly = !interactive())
library(utils,quietly = !interactive())
library(matrixStats,quietly = !interactive())


estimate.two.component.bayesian.mixture <- function(ints,depth,N=1100,burnin=100,pruning=NULL,with.distance.weight=F,multiply=T,show.progress=F) {
  S <- nrow(ints)
  
  d <- GRanges(seqnames=as.character(depth$V1),ranges=IRanges(depth$V2,depth$V3),strand='*')
  g1 <- GRanges(seqnames=as.character(ints$V1),ranges=IRanges(ints$V2,ints$V3),strand='*')
  g2 <- GRanges(seqnames=as.character(ints$V4),ranges=IRanges(ints$V5,ints$V6),strand='*')
  
  m1 <- match(g1,d)
  m2 <- match(g2,d)
  counts <- ints[,7]
  d <- depth[,4]
  
  if(!multiply) {
    sdepth <- rowSums(cbind(d[m1],d[m2]))
    msdepth <- median(sdepth)
  } else {
    sdepth <- rowProds(cbind(d[m1],d[m2]))
    msdepth <- median(sdepth)
  }
  
  print(c(msdepth,range(sdepth)))
  
  l <- lapply(1:S,function(i) list(z=rep(NA_integer_,N),mp=rep(NA_real_,N)))
  pp <- c(.5,rep(NA_real_,N))
  
  lambda0 <- c(1,rep(NA_real_,N))
  lambda1 <- c(5,rep(NA_real_,N))
  
  
  totcounts <- sum(counts)
  
  
  if(show.progress) pb <- txtProgressBar()
  
  
  for( i in 1:N ) {
    #vp <- f(pp,lambda1[i],lambda0[i])
    g1 <- pp[i]*dpois(counts,lambda1[i])
    g2 <- (1-pp[i]) * dpois(counts,lambda0[i])
    
    vp <- g1/rowSums(cbind(g1,g2)) 
    if(any(is.na(vp))) {
      b<- is.na(vp)
      vp[b] <- as.integer(counts[b]>=lambda1[i])
    }
    vz <- rbinom(S,1,vp)
    
    ipos <- sum(vz)
    pp[i+1] <- rbeta(1,1+ipos,1+S-ipos) 
    
    l <- mapply(function(lx,z,mp){
      lx$z[i] <- z
      lx$mp[i] <- mp
      lx
    },l,as.list(vz),as.list(vp),SIMPLIFY=F)
    
    l0 <- 0
    r <- sum(counts[vz==0])
    n <- sum(vz==0)
    
    l0 <- rgamma(1,r,n)
    
    l1 <- l0
    #r <- totcounts - r #sum(counts[vz==1])
    
    l1x <- rgamma(1,totcounts-r,S-n)#sum(vz==1))
    l1 <- max(l1,l1x)
    
    lambda0[i+1] <- l0
    lambda1[i+1] <- l1
    
    print(c(l0,l1))
    if(show.progress) setTxtProgressBar(pb,i/N)
  }
  
  if(show.progress) close(pb)
  ret <- list(s=l,l0=lambda0,l1=lambda1,pp=pp)
  if(!is.null(burnin) && is.numeric(burnin) && burnin > 0) {
    orig <- ret
    idx <- -(1:burnin)
    ret <- lapply(ret,function(v) v[idx])
    ret$orig <- orig
  }
  ret <- c(ret,list(sdepth=sdepth,msdepth=msdepth))
  ret
}

extract.two.component.bayesian.mixture.prob <- function(model) {
  sapply(model$s,function(v) sum(v$z)/length(v$z))
}
