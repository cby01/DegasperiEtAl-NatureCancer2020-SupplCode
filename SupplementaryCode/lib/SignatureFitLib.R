#Fork of SigFit from Sandro Morganella 2017
#Andrea Degasperi, andrea.degasperi@sanger.ac.uk
library(NNLM)
library(nnls)

SignatureFit <- function(cat, #catalogue, patients as columns, channels as rows
                         signature_data_matrix,  #signatures, signatures as columns, channels as rows
                         method = "KLD", #KLD or NNLS or SA
                         bf_method = "CosSim", #KLD or CosSim
                         alpha = -1, #set alpha to -1 to avoid Bleeding Filter
                         doRound = TRUE, #round the exposures to the closest integer
                         verbose = TRUE, #use FALSE to suppress messages
                         n_sa_iter = 500){ 
  if(method=="KLD"){
    if(verbose) message("SignatureFit, objective function: KLD")
    
    #Fit using the given signatures
    nnlm_res <- nnlm(as.matrix(signature_data_matrix),as.matrix(cat),loss = "mkl",method = "lee")
    fit_KLD <- KLD(cat,as.matrix(signature_data_matrix) %*% nnlm_res$coefficients)
    exposures <- nnlm_res$coefficients
    if(verbose) message("Optimisation terminated, KLD=",fit_KLD)
    if(alpha >= 0){ #negative alpha skips Bleeding Filter
      #apply bleeding filter
      if(bf_method=="CosSim"){
        if(verbose) message("Applying Bleeding Filter (Cosine Similarity) with alpha=",alpha*100,"%")
      }else if (bf_method=="KLD"){
        if(verbose) message("Applying Bleeding Filter (KLD) with alpha=",alpha*100,"%")
      }
      for(i in 1:ncol(nnlm_res$coefficients)){
        if(bf_method=="CosSim"){
          exposures[,i] <- bleedingFilter(e = nnlm_res$coefficients[,i],
                                             sig = signature_data_matrix,
                                             sample = cat[,i],
                                             alpha = alpha)
        }else if (bf_method=="KLD"){
          exposures[,i] <- bleedingFilterKLD(e = nnlm_res$coefficients[,i],
                                             sig = signature_data_matrix,
                                             sample = cat[,i],
                                             alpha = alpha)
        }
      }
      fit_KLD_afterBF <- KLD(cat,as.matrix(signature_data_matrix) %*% exposures)
      if(verbose) message("New fit after Bleeding Filter, KLD=",fit_KLD_afterBF," (",sprintf("%.3f",(fit_KLD_afterBF - fit_KLD)/fit_KLD*100),"% increase)")
    }
  }else if(method=="SA"){
    library(GenSA)
    library(foreach)
    library(doParallel)
    library(doMC)
    
    registerDoParallel(4)
    
    if(verbose) message("SignatureFit, objective function: SA")
    
    sig <- signature_data_matrix
    
    
    #---- copy from Sandro's code below
    exp_list <- foreach(j=1:ncol(cat)) %dopar% {	
      curr_cat <- as.numeric(cat[,j])
      nmut <- sum(curr_cat)
      exp_tmp <- rep(0, ncol(sig))
      names(exp_tmp) <- names(sig)
      if(nmut>0){
        if(verbose) message("Analyzing " ,  j, " of ", ncol(cat), " sample name ", colnames(cat[j]))
        
        ## Compute the start solution for the sim. annealing
        ss <- startSolution(sig, curr_cat)
        
        ## Compute the exposure by using the sim. annealing
        out <- GenSA(par=as.numeric(ss), lower=rep(0, ncol(sig)), upper=rep(nmut, ncol(sig)), fn=objSimAnnelaingFunction, control=list(maxit=n_sa_iter), xsample=curr_cat, xsignature=sig)
        
        exp_tmp <- as.numeric(out$par)
        if(sum(exp_tmp)==0){
          exp_tmp <- ss
        }else{
          exp_tmp <- (exp_tmp/sum(exp_tmp))*nmut
        }
        names(exp_tmp) <- names(ss)
        
        ## Apply the bleeding Filter to remove the 'unnecessary' signatures
        if(bf_method=="CosSim"){
          if(verbose) message("Applying Bleeding Filter (Cosine Similarity) with alpha=",alpha*100,"%")
          exp_tmp <-  bleedingFilter(exp_tmp, sig, curr_cat, alpha)
        }else if (bf_method=="KLD"){
          if(verbose) message("Applying Bleeding Filter (KLD) with alpha=",alpha*100,"%")
          exp_tmp <-  bleedingFilterKLD(exp_tmp, sig, curr_cat, alpha)
        }
        
      }
      exp_tmp
    }
    
    exposures <- matrix(unlist(exp_list), ncol=ncol(sig), byrow=T)
    rownames(exposures) <- colnames(cat)
    colnames(exposures) <- colnames(sig)
    exposures <- t(exposures)
    #----- end of Sandro's code
    

    
  }else if(method=="NNLS"){
    if(verbose) message("SignatureFit, method: NNLS")
    
    exposures <- matrix(NA,ncol = ncol(cat),nrow = ncol(signature_data_matrix))
    colnames(exposures) <- colnames(cat)
    rownames(exposures) <- colnames(signature_data_matrix)
    for (i in 1:ncol(cat)){
      q <- as.vector(cat[,i])
      exp_NNLS <- nnls(as.matrix(signature_data_matrix),q)
      exposures[,i] <- exp_NNLS$x
    }
    
    fit_KLD <- KLD(cat,as.matrix(signature_data_matrix) %*% exposures)
    if(verbose) message("Optimisation terminated, KLD=",fit_KLD)
    
    if(alpha >= 0){ #negative alpha skips Bleeding Filter
      #apply bleeding filter
      if(bf_method=="CosSim"){
        if(verbose) message("Applying Bleeding Filter (Cosine Similarity) with alpha=",alpha*100,"%")
      }else if (bf_method=="KLD"){
        if(verbose) message("Applying Bleeding Filter (KLD) with alpha=",alpha*100,"%")
      }
      for (i in 1:ncol(exposures)){
        if(bf_method=="CosSim"){
          exposures[,i] <- bleedingFilter(e = exposures[,i],
                                          sig = signature_data_matrix,
                                          sample = cat[,i],
                                          alpha = alpha)
        }else if (bf_method=="KLD"){
          exposures[,i] <- bleedingFilterKLD(e = exposures[,i],
                                             sig = signature_data_matrix,
                                             sample = cat[,i],
                                             alpha = alpha)
        }
      }
    }
    fit_KLD_afterBF <- KLD(cat,as.matrix(signature_data_matrix) %*% exposures)
    if(verbose) message("New fit after Bleeding Filter, KLD=",fit_KLD_afterBF," (",sprintf("%.3f",(fit_KLD_afterBF - fit_KLD)/fit_KLD*100),"% increase)")
  }else{
    stop("SignatureFit error. Unknown method specified.")
  }
  exposures[exposures < .Machine$double.eps] <- 0
  if(doRound) exposures <- round(exposures)
  return(exposures)
}


#implementation of method similar to
#Huang 2017, Detecting presence of mutational signatures with confidence
SignatureFit_withBootstrap <- function(cat, #catalogue, patients as columns, channels as rows
                          signature_data_matrix, #signatures, signatures as columns, channels as rows
                          nboot = 50, #number of bootstraps to use, more bootstraps more accurate results
                          threshold_percent = 1, #threshold in percentage of total mutations in a sample, only exposures larger than threshold are considered
                          threshold_p.value = 0.05, #p-value to determine whether an exposure is above the threshold_percent. In other words, this is the empirical probability that the exposure is lower than the threshold
                          method = "KLD", #KLD or SA, just don't use SA or you will wait forever, expecially with many bootstraps. SA is ~1000 times slower than KLD or NNLS
                          bf_method = "CosSim", #KLD or CosSim, only used if alpha != -1
                          alpha = -1, #set alpha to -1 to avoid Bleeding Filter
                          verbose=TRUE, #use FALSE to suppress messages
                          doRound = TRUE, #round the exposures to the closest integer
                          nparallel=1, #to use parallel specify >1
                          n_sa_iter = 500){ #only used if  method = "SA"
  if (nparallel > 1){
    library(foreach)
    library(doParallel)
    library(doMC)
    registerDoParallel(4)
    boot_list <- foreach(j=1:nboot) %dopar% {
      bootcat <- generateRandMuts(cat)
      SignatureFit(bootcat,signature_data_matrix,method,bf_method,alpha,verbose=verbose,doRound = doRound,n_sa_iter=n_sa_iter)
    }
  }else{
    boot_list <- list()
    for(i in 1:nboot){
      bootcat <- generateRandMuts(cat)
      boot_list[[i]] <- SignatureFit(bootcat,signature_data_matrix,method,bf_method,alpha,verbose=verbose,doRound = doRound,n_sa_iter=n_sa_iter)
    }
  }

  samples_list <- list()
  for(i in 1:ncol(cat)) {
    samples_list[[i]] <- matrix(NA,ncol = nboot,nrow = ncol(signature_data_matrix))
    colnames(samples_list[[i]]) <- 1:nboot
    row.names(samples_list[[i]]) <- colnames(signature_data_matrix)
  }
  for(i in 1:nboot){
    for(j in 1:ncol(cat)){
      samples_list[[j]][,i] <- boot_list[[i]][,j]
    }
  }
  #-- tests
  # boxplot(t(samples_list[[1]]))
  # points(1:10,E[,1],col="red")
  # plot(samples_list[[1]][3,],samples_list[[1]][6,])
  #--
  E_median_notfiltered <- matrix(NA,nrow = ncol(signature_data_matrix),ncol = ncol(cat))
  E_median_filtered <- matrix(NA,nrow = ncol(signature_data_matrix),ncol = ncol(cat))
  E_p.values <- matrix(NA,nrow = ncol(signature_data_matrix),ncol = ncol(cat))
  colnames(E_median_notfiltered) <- colnames(cat)
  row.names(E_median_notfiltered) <- colnames(signature_data_matrix)
  colnames(E_median_filtered) <- colnames(cat)
  row.names(E_median_filtered) <- colnames(signature_data_matrix)
  colnames(E_p.values) <- colnames(cat)
  row.names(E_p.values) <- colnames(signature_data_matrix)
  #KLD error vector
  KLD_samples <- c()
  
  for(i in 1:ncol(cat)) {
    boots_perc <- samples_list[[i]]/matrix(apply(samples_list[[i]],2,sum),byrow = TRUE,nrow = nrow(samples_list[[i]]),ncol = ncol(samples_list[[i]]))*100
    p.values <- apply(boots_perc <= threshold_percent,1,sum)/nboot
    median_mut <- apply(samples_list[[i]],1,median)
    E_median_notfiltered[,i] <- median_mut
    E_p.values[,i] <- p.values
    
    median_mut_perc <- median_mut/sum(median_mut)*100
    # plot(median_mut_perc)
    # abline(h=5)
    median_mut_perc[p.values > threshold_p.value] <- 0
    #below rescaling, not sure whether to use it or not. If not I have something like a residual
    # median_mut_perc <- median_mut_perc/sum(median_mut_perc)*100
    median_mut <- median_mut_perc/100*sum(cat[,i])
    # boxplot(t(samples_list[[1]]))
    # points(1:10,E[,1],col="red")
    # points(1:10,median_mut,col="green")
    E_median_filtered[,i] <- median_mut
    KLD_samples <- c(KLD_samples,KLD(cat[,i,drop=FALSE],as.matrix(signature_data_matrix) %*% E_median_filtered[,i,drop=FALSE]))
  }
  names(KLD_samples) <- colnames(cat)
  
  res <- list()
  res$E_median_filtered <- E_median_filtered
  res$E_p.values <- E_p.values
  res$samples_list <- samples_list
  res$boot_list <- boot_list
  res$KLD_samples <- KLD_samples
  #need metadata
  res$threshold_percent <- threshold_percent
  res$threshold_p.value <- threshold_p.value
  res$nboots <- nboot
  res$method <- method
  return(res)
}

RMSE <- function(m1,m2){
  sqrt(sum((m1-m2)^2)/(ncol(m1)*nrow(m1)))
}

SignatureFit_withBootstrap_Analysis <- function(outdir, #output directory for the analysis, remember to add '/' at the end
                                                cat, #catalogue, patients as columns, channels as rows
                                       signature_data_matrix, #signatures, signatures as columns, channels as rows
                                       nboot = 50, #number of bootstraps to use, more bootstraps more accurate results
                                       type_of_mutations="subs", #use one of c("subs","rearr","generic")
                                       threshold_percent = 1, #threshold in percentage of total mutations in a sample, only exposures larger than threshold are considered
                                       threshold_p.value = 0.05, #p-value to determine whether an exposure is above the threshold_percent. In other words, this is the empirical probability that the exposure is lower than the threshold
                                       method = "KLD", #KLD or SA, just don't use SA or you will wait forever, expecially with many bootstraps. SA is ~1000 times slower than KLD or NNLS
                                       bf_method = "CosSim", #KLD or CosSim, only used if alpha != -1
                                       alpha = -1, #set alpha to -1 to avoid Bleeding Filter
                                       doRound = TRUE, #round the exposures to the closest integer
                                       nparallel=1, #to use parallel specify >1
                                       n_sa_iter = 500){  #only used if  method = "SA"
  # outdir <- "../results/sigfitbootstraptests/"
  dir.create(outdir,recursive = TRUE,showWarnings = FALSE)
  
  #begin by computing the sigfit bootstrap
  file_store <- paste0(outdir,"SigFit_withBootstrap_Summary_m",method,"_bfm",bf_method,"_alpha",alpha,"_tr",threshold_percent,"_p",threshold_p.value,".rData")
  if(file.exists(file_store)){
    load(file_store)
    message("Bootstrap Signature Fits loaded from file")
  }else{
    res <- SignatureFit_withBootstrap(cat = cat,
                                          signature_data_matrix = signature_data_matrix,
                                          nboot = nboot,
                                          threshold_percent = threshold_percent,
                                          threshold_p.value = threshold_p.value,
                                          method = method,
                                          bf_method = bf_method,
                                          alpha = alpha,
                                          doRound = doRound,
                                          nparallel = nparallel,
                                          n_sa_iter = n_sa_iter)
    save(file = file_store,res,nboot)
  }
  
  
  source("../lib/SignatureExtractionLib.R")
  #library(gplots)
  
  #function to draw a legend for the heatmap of the correlation matrix
  draw_legend <- function(col,xl,xr,yb,yt){
    par(xpd=TRUE)
    rect(xl,yb,xr,yt)
    rect(
      xl,
      head(seq(yb,yt,(yt-yb)/length(col)),-1),
      xr,
      tail(seq(yb,yt,(yt-yb)/length(col)),-1),
      col=col,border = NA
    )
    text(x = 1.2, y = yt,labels = "1")
    text(x = 1.2, y = (yt-yb)/2,labels = "0")
    text(x = 1.2, y = yb,labels = "-1")
  }
  
  reconstructed_with_median <- as.matrix(signature_data_matrix) %*% res$E_median_filtered
  #provide a series of plots for each sample
  #plot_nrows <- ncol(cat)
  rows_ordered_from_best <- order(res$KLD_samples)
  plot_nrows <- 2
  plot_ncol <- 4
  nplots <- plot_nrows*plot_ncol
  howmanyplots <- ncol(cat)
  plotsdir <- paste0(outdir,"SigFit_withBootstrap_Summary_m",method,"_bfm",bf_method,"_alpha",alpha,"_tr",threshold_percent,"_p",threshold_p.value,"/")
  dir.create(plotsdir,recursive = TRUE,showWarnings = FALSE)
  for(p in 1:howmanyplots){
    # if (plot_nrows+(p-1)*plot_nrows>=length(rows_ordered_from_best)){
    #   current_samples <- rows_ordered_from_best[1:plot_nrows+(p-1)*plot_nrows]
    # }else{
    #   current_samples <- rows_ordered_from_best[(1+(p-1)*plot_nrows):length(rows_ordered_from_best)]
    # }
    current_samples <- p
    jpeg(filename = paste0(plotsdir,"sigfit_bootstrap_",p,"of",howmanyplots,".jpg"),
         width = 640*(plot_ncol),
         height = 480*plot_nrows,
         res = 150)
    par(mfrow=c(plot_nrows,plot_ncol))
    for(i in current_samples){
      percentdiff <- sprintf("%.2f",sum(abs(cat[,i,drop=FALSE] - reconstructed_with_median[,i,drop=FALSE]))/sum(cat[,i,drop=FALSE])*100)
      if(type_of_mutations=="subs"){
        #1 original
        plotSubsSignatures(signature_data_matrix = cat[,i,drop=FALSE],add_to_titles = "Catalogue",mar=c(6,3,5,2))
        if(sum(cat[,i,drop=FALSE])>0){
          #2 reconstructed
          plotSubsSignatures(signature_data_matrix = reconstructed_with_median[,i,drop=FALSE],add_to_titles = "Model",mar=c(6,3,5,2))
          #3 difference
          plotSubsSignatures(signature_data_matrix = cat[,i,drop=FALSE] - reconstructed_with_median[,i,drop=FALSE],add_to_titles = paste0("Difference, ",percentdiff,"%"),mar=c(6,3,5,2))
        }
      }else if(type_of_mutations=="rearr"){
        #1 original
        plotRearrSignatures(signature_data_matrix = cat[,i,drop=FALSE],add_to_titles = "Catalogue",mar=c(12,3,5,2))
        if(sum(cat[,i,drop=FALSE])>0){
          #2 reconstructed
          plotRearrSignatures(signature_data_matrix = reconstructed_with_median[,i,drop=FALSE],add_to_titles = "Model",mar=c(12,3,5,2))
          #3 difference
          plotRearrSignatures(signature_data_matrix = cat[,i,drop=FALSE] - reconstructed_with_median[,i,drop=FALSE],add_to_titles = paste0("Difference, ",percentdiff,"%"),mar=c(12,3,5,2))
        }
      }else if(type_of_mutations=="generic"){
        #1 original
        plotGenericSignatures(signature_data_matrix = cat[,i,drop=FALSE],add_to_titles = "Catalogue",mar=c(6,3,5,2))
        if(sum(cat[,i,drop=FALSE])>0){
          #2 reconstructed
          plotGenericSignatures(signature_data_matrix = reconstructed_with_median[,i,drop=FALSE],add_to_titles = "Model",mar=c(6,3,5,2))
          #3 difference
          plotGenericSignatures(signature_data_matrix = cat[,i,drop=FALSE] - reconstructed_with_median[,i,drop=FALSE],add_to_titles = paste0("Difference, ",percentdiff,"%"),mar=c(6,3,5,2))
        }
      }
      if(sum(cat[,i,drop=FALSE])>0){
        #4 bootstraps
        par(mar=c(6,4,5,2))
        boxplot(t(res$samples_list[[i]]),las=3,cex.axes=0.9,
                ylab="n mutations",
                ylim=c(0,max(res$samples_list[[i]])),
                main=paste0("Exposures, of ",colnames(res$E_median_filtered)[i],"\nthreshold=",threshold_percent,"%, p-value=",threshold_p.value,", n=",nboot))
        points(1:length(res$E_median_filtered[,i,drop=FALSE]),res$E_median_filtered[,i,drop=FALSE],col="red")
        abline(h=threshold_percent/100*sum(cat[,i,drop=FALSE]),col="green")
        legend(x="topleft",legend = c("consensus exposures"),col = "red",pch = 1,cex = 0.9,bty = "n",inset = c(0,-0.14),xpd = TRUE)
        legend(x="topright",legend = c("threshold"),col = "green",lty = 1,cex = 0.9,bty = "n",inset = c(0,-0.14),xpd = TRUE)
        if(ncol(signature_data_matrix)>1){
          #5 top correlated signatures
          res.cor <- cor(t(res$samples_list[[i]]),method = "spearman")
          res.cor_triangular <- res.cor
          res.cor_triangular[row(res.cor)+(ncol(res.cor)-col(res.cor))>=ncol(res.cor)] <- 0
          res.cor_triangular_label <- matrix(sprintf("%0.2f",res.cor_triangular),nrow = nrow(res.cor_triangular))
          res.cor_triangular_label[row(res.cor)+(ncol(res.cor)-col(res.cor))>=ncol(res.cor)] <- ""
          # heatmap(res.cor_triangular,
          #           Rowv = NA,
          #           Colv = NA,
          #           scale = "none",
          #           col = col,
          #           symm = TRUE,
          #           breaks=seq(-1,1,length.out = 52))
          par(mar=c(6,8,5,6))
          par(xpd=FALSE)
          col<- colorRampPalette(c("blue", "white", "red"))(51)
          image(res.cor_triangular,col = col,zlim = c(-1,1), axes=F,main="Exposures Correlation (spearman)")
          extrabit <- 1/(ncol(signature_data_matrix)-1)/2
          abline(h=seq(0-extrabit,1+extrabit,length.out = ncol(signature_data_matrix)+1),col="grey",lty=2)
          abline(v=seq(0-extrabit,1+extrabit,length.out = ncol(signature_data_matrix)+1),col="grey",lty=2)
          axis(2,at = seq(0,1,length.out = ncol(signature_data_matrix)),labels = colnames(signature_data_matrix),las=1,cex.lab=0.8)
          axis(1,at = seq(0,1,length.out = ncol(signature_data_matrix)),labels = colnames(signature_data_matrix),las=2,cex.lab=0.8)
          draw_legend(col,1.25,1.3,0,1)
          
          #6 some correlation plots
          #pos <- which(max(abs(res.cor_triangular))==abs(res.cor_triangular),arr.ind = TRUE)
          vals <- res.cor_triangular[order(abs(res.cor_triangular),decreasing = TRUE)]
          for (j in 1:(nplots-5)){
            pos <- which(vals[j]==res.cor_triangular,arr.ind = TRUE)
            mainpar <- paste0("Exposures across bootstraps, n=",nboot,"\nspearman correlation ",sprintf("%.2f",vals[j]))
            plot(res$samples_list[[i]][pos[1],],res$samples_list[[i]][pos[2],],
                 xlab = colnames(signature_data_matrix)[pos[1]],
                 ylab = colnames(signature_data_matrix)[pos[2]],
                 # ylim = c(0,max(res$samples_list[[i]][pos[2],])),
                 # xlim = c(0,max(res$samples_list[[i]][pos[1],]))
                 main=mainpar,col="blue",pch = 16)
    
          }
          #sig.pca <- prcomp(t(res$samples_list[[i]]),center = TRUE,scale. = TRUE)
        }
      }
    }
    dev.off()
  }
  # res$E_median_filtered[,i,drop=FALSE]
  
  
  return(res)
}

## This Function removes the 'unnecesary' signatures
#optimise w.r.t. cosine similarity
#alpha is the max cosine similarity that can be lost 
bleedingFilter <- function(e, sig,  sample, alpha){
  ## Compute the cosine similarity between the current solution and the catalogue
  #sim_smpl <- computeSimSample(e, sample, sig)
  sim_smpl <- as.matrix(sig) %*% e
  val <- cos.sim(sample, sim_smpl)
  
  e_orig <- e
  delta <- 0
  
  
  while(delta<=alpha && length(which(e>0))>1){
    
    pos <- which(e>0)
    e <- e[pos]
    sig <- sig[,pos]
    sim_m <- matrix(0, ncol(sig), ncol(sig))
    colnames(sim_m) <- names(e)
    rownames(sim_m) <- names(e)
    
    ## Move mutations across each pair of signatures and estimate the cosine similarity of the new solution		
    for(i in 1:ncol(sig)){
      for(j in 1:ncol(sig)){
        if(i!=j){
          e2 <- e
          e2[j] <- e2[j]+e2[i]
          e2[i] <- 0
          #sim_smpl <- computeSimSample(e2, sample, sig)
          sim_smpl <- as.matrix(sig) %*% e2
          sim_m[i,j] <- cos.sim(sample, sim_smpl)	
        }
      }
    }
    
    ## Extract the minimum delta
    delta <- val-max(sim_m)
    
    # If delta <= alpha accept the new solution
    if(delta<=alpha){
      pos <-  which(sim_m==max(sim_m), arr.ind=T)
      e[pos[1,2]] <- e[pos[1,2]]+e[pos[1,1]]
      e[pos[1,1]] <- 0
    }
  }
  
  e_orig[] <- 0
  e_orig[names(e)] <- e
  
  return(e_orig)
}

## This Function removes the 'unnecesary' signatures
#optimise w.r.t. KLD
#alpha is the max ratio of KLD that can be lost (e.g. 0.01 is 1% of original KLD)
bleedingFilterKLD <- function(e, sig,  sample, alpha){
  ## Compute the cosine similarity between the current solution and the catalogue
  #sim_smpl <- computeSimSample(e, sample, sig)
  sim_smpl <- as.matrix(sig) %*% e
  val <- KLD(sample, sim_smpl)
  alpha <- alpha*val
  
  e_orig <- e
  delta <- 0
  
  
  while(delta<=alpha && length(which(e>0))>1){
    
    pos <- which(e>0)
    e <- e[pos]
    sig <- sig[,pos]
    sim_m <- matrix(0, ncol(sig), ncol(sig))
    colnames(sim_m) <- names(e)
    rownames(sim_m) <- names(e)
    
    ## Move mutations across each pair of signatures and estimate the cosine similarity of the new solution		
    for(i in 1:ncol(sig)){
      for(j in 1:ncol(sig)){
        if(i!=j){
          e2 <- e
          e2[j] <- e2[j]+e2[i]
          e2[i] <- 0
          #sim_smpl <- computeSimSample(e2, sample, sig)
          sim_smpl <- as.matrix(sig) %*% e2
          sim_m[i,j] <- KLD(sample, sim_smpl)	
        }
      }
    }
    sim_m <- sim_m + diag(nrow(sim_m))*1e6
    ## Extract the minimum delta
    delta <- min(sim_m)-val
    
    # If delta <= alpha accept the new solution
    if(delta<=alpha){
      pos <-  which(sim_m==min(sim_m), arr.ind=T)
      e[pos[1,2]] <- e[pos[1,2]]+e[pos[1,1]]
      e[pos[1,1]] <- 0
    }
  }
  
  e_orig[] <- 0
  e_orig[names(e)] <- e
  
  return(e_orig)
}

KLD <- function(m1,m2){
  # print(sessionInfo())
  # print(m1)
  # print(m2)
  # m1 <- as.vector(as.matrix(cat))
  # m2 <- as.vector(as.matrix(m2))
  m1[m1==0] <- .Machine$double.eps
  m2[m2==0] <- .Machine$double.eps
  return(sum(m1*(log(m1)-log(m2)) - m1 + m2))
}

#compute the cosine similarity
cos.sim <- function(a, b){
  return( sum(a*b)/sqrt(sum(a^2)*sum(b^2)) )
} 

## Function to generate the start solution for the sim. annelaing
startSolution <- function(sig, cat){
  summ <- apply(sig, 1, sum)
  out <- (sig/summ)*cat
  pos <- which(is.nan(as.matrix(out)), arr.ind=T)
  if(length(pos)>0){
    out[pos] <- 0
  }
  return(apply(out, 2, sum))
}

## The Objective Function fot the simulated annelaing
objSimAnnelaingFunction <- function(x, xsample, xsignature){
  sim_smpl <- rep(0, length(xsample))
  for(i in 1:ncol(xsignature)){
    sim_smpl  <- sim_smpl+(xsignature[,i]*x[i])
  }
  sum(abs(xsample-sim_smpl))
}

## Given the exposure and the probability matrix compute the Catalogue 
# computeSimSample <- function(x, xsample, xsignature){
#   sim_smpl <- rep(0, length(xsample))
#   for(i in 1:ncol(xsignature)){
#     sim_smpl  <- sim_smpl+(xsignature[,i]*x[i])
#   }
#   return(sim_smpl)
# }

## Generate a random replicate of the cataloge 
# This method guarantees the total number of signatures is unchanged
generateRandMuts <- function(x){
  #consider the following method as a replacement
  full_r <- matrix(nrow = dim(x)[1],ncol = dim(x)[2])
  colnames(full_r) <- colnames(x)
  row.names(full_r) <- row.names(x)
  for (i in 1:ncol(x)){
    if(sum(x[,i]>0)){
      samples <- sample(1:nrow(x),size = sum(x[,i]),prob = x[,i]/sum(x[,i]),replace = TRUE)
      r <- unlist(lapply(1:nrow(x),function(p) sum(samples==p)))
    }else{ #no rearrangments found
      r <- x[,i]
    }
    names(r) <- rownames(x)
    full_r[,i] <- r
  }
  return(full_r)
}


plot.exposures <- function(exposures,output_file,dpi=300){
  library("ggplot2")
  
  # Set up the vectors                           
  signatures.names <- colnames(exposures)
  sample.names <- row.names(exposures)
  
  # Create the data frame
  df <- expand.grid(sample.names,signatures.names)
  df$value <- unlist(exposures)   
  df$labels <- sprintf("%.2f", df$value)
  df$labels[df$value==0] <- ""
  
  #Plot the Data (500+150*nsamples)x1200
  g <- ggplot(df, aes(Var1, Var2)) + geom_point(aes(size = value), colour = "green") + theme_bw() + xlab("") + ylab("")
  g <- g + scale_size_continuous(range=c(0,10)) + geom_text(aes(label = labels))
  g + theme(axis.text.x = element_text(angle = 90, hjust = 1, size=14),
            axis.text.y = element_text(vjust = 1, size=14))
  w <- (500+150*length(sample.names))/dpi
  h <- (500+150*length(signatures.names))/dpi
  ggsave(filename = output_file,dpi = dpi,height = h,width = w,limitsize = FALSE)
}

#export to json for web visualisation
export_SignatureFit_withBootstrap_to_JSON <- function(outdir,res){
  
  dir.create(outdir,showWarnings = FALSE,recursive = TRUE)
  #plot consensus exposures file with metadata
  consensus_file <- paste0(outdir,"consensus.json")
  sink(file = consensus_file)
  cat("{\n")
  cat("\t\"nboots\": ",res$nboots,",\n",sep = "")
  cat("\t\"threshold_percent\": ",res$threshold_percent,",\n",sep = "")
  cat("\t\"threshold_p.value\": ",res$threshold_p.value,",\n",sep = "")
  cat("\t\"method\": \"",res$method,"\",\n",sep = "")
  cat("\t\"consensus\": {\n",sep = "")
  
  for(i in 1:ncol(res$E_median_filtered)){
    sname <- colnames(res$E_median_filtered)[i]
    cat("\t\t\"",sname,"\": {\n",sep = "")
    
    for(j in 1:nrow(res$E_median_filtered)){
      rname <- rownames(res$E_median_filtered)[j]
      cat("\t\t\t\"",rname,"\": ",res$E_median_filtered[j,i],sep = "")
      if(j<nrow(res$E_median_filtered)){
        cat(",\n")
      }else{
        cat("\n")
      }
    }
    
    cat("\t\t}")
    if(i<ncol(res$E_median_filtered)){
      cat(",\n")
    }else{
      cat("\n")
    }
  }
  
  cat("\t}\n")
  cat("}\n")
  sink()
  
  #plot bootstraps exposures file 
  boot_file <- paste0(outdir,"bootstraps.json")
  sink(file = boot_file)
  cat("[\n")
  
  for (b in 1:length(res$boot_list)){
    data_mat <- res$boot_list[[b]]
    
    cat("\t{\n")
    
    for(i in 1:ncol(data_mat)){
      sname <- colnames(data_mat)[i]
      cat("\t\t\"",sname,"\": {\n",sep = "")
      
      for(j in 1:nrow(data_mat)){
        rname <- rownames(data_mat)[j]
        cat("\t\t\t\"",rname,"\": ",data_mat[j,i],sep = "")
        if(j<nrow(data_mat)){
          cat(",\n")
        }else{
          cat("\n")
        }
      }
      
      cat("\t\t}")
      if(i<ncol(data_mat)){
        cat(",\n")
      }else{
        cat("\n")
      }
    }
    
    cat("\t}")
    if(b<length(res$boot_list)){
      cat(",\n")
    }else{
      cat("\n")
    }
    
  }
  cat("]\n")
  sink()
  
  #plot correlation of exposures file for each sample
  for (s in 1:ncol(res$E_median_filtered)){
    if (nrow(res$samples_list[[s]])>1){
      sname <- colnames(res$E_median_filtered)[s]
      data_mat <- cor(t(res$samples_list[[s]]),method = "spearman")
      data_mat[is.na(data_mat)] <- 0
      data_mat[row(data_mat)+(ncol(data_mat)-col(data_mat))>=ncol(data_mat)] <- 0
      
      cor_file <- paste0(outdir,sname,"_correlation.tsv")
      sink(file = cor_file)
      cat("Signature")
      for (j in colnames(data_mat)) cat("\t",j,sep = "")
      cat("\n")
      
      for(i in 1:nrow(data_mat)){
        cat(row.names(data_mat)[i])
        for (j in 1:ncol(data_mat)) cat("\t",data_mat[i,j],sep = "")
        cat("\n")
      }
      
      sink()
    }
  }

}

