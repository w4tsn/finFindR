#' @title cropFins 
#' @details Function loads image and uses the given neural network to isolate any dorsal fins therin.
#' The neural network returns a matrix whose values range [0,1].
#' Using a contiguous region algorithm (blob analysis),
#' the x,y range for each excitation on the matrix is found.
#' The range is then rescaled to find the analogous region in the original image.
#' This region is cropped from said image and saved as a jpeg to the given directory.
#' @param imageName path to image to be cropped
#' @param workingImage workspace for holding image during processing
#' @param cropNet mxnet model for isolating dolphin
#' @param saveDir directory to save cropped image
#' @param minXY minimum width/height in pixels for valid crop
#' @param target label indicating layer representing class
#' @param threshold threshold value for triggering a crop
#' @export
cropFins <- function(imageName,cropNet,workingImage,saveDir,minXY=100,target=1,threshold=.45,dim=c(225,150,3,1))
{
  if(!("MXFeedForwardModel" %in% class(cropNet))){stop("network must be of class MXFeedForwardModel")}
  workingImage$origImg <-  suppressWarnings( as.cimg(aperm(jpeg::readJPEG(imageName,F),c(2,1,3))) )
  gc()
  image <- resize(workingImage$origImg,size_x = dim[1], size_y = dim[2], interpolation_type = 3)
  dim(image) <- dim
  image <- image/max(image)
  
  netOut <- mxnet:::predict.MXFeedForwardModel(X=image,
                                               model=cropNet,
                                               ctx=mxnet::mx.cpu(),
                                               array.layout = "colmajor")
  targetIsolate <- isoblur(suppressWarnings(as.cimg(netOut[,,target,])),.5)
  if(length(target)>1)
  {
    targetIsolate <- parmax(imsplit(targetIsolate,axis='c'))
    blobs <- erode_square(label(dilate_square(targetIsolate > (threshold/2), 3),high_connectivity=F),3) 
    
  }else{
    netOutThresh <- targetIsolate > (threshold/2)
    connectionBuffer <- dilate_rect(netOutThresh,sx=9,sy=9,sz=1)
    corr <- parmax(imsplit(suppressWarnings(as.cimg(netOut[,,-target,] > (threshold/2))),axis='c'))
    
    tightened <- erode_square(netOutThresh,3)
    overlap <- tightened | (connectionBuffer & erode_square(corr,3) )
    blobs <- tightened * label(overlap,high_connectivity=T)
  }
  
  edges <- targetIsolate>threshold
  
  keepers <- table(blobs*edges)
  if(length(keepers) > 1)
  {
    print(paste(length(keepers)-1,"fin(s)"))
    blobs[!(blobs %in% as.integer(names(which(keepers>1))))] <- 0
    
    #crop out each fin
    blobInc <- 0
    for(blobValue in unique(blobs)[which(unique(blobs)>0)])
    {
      blobInc <- blobInc+1
      blobCoordinates <- get.locations(blobs,function(x)x==blobValue)-1
      
      width <- max(blobCoordinates$x)-min(blobCoordinates$x)
      height <- max(blobCoordinates$y)-min(blobCoordinates$y)
      
      if(max(width,height) < 3*min(width,height))
      {
        marginX <- ceiling((width)/3)
        marginY <- ceiling((height)/3)
        
        mainImgName <- strsplit(basename(imageName),"\\.")[[1]][1]
        
        stretchX <- ceiling(width(workingImage$origImg)/width(image))
        stretchY <- ceiling(height(workingImage$origImg)/height(image))
        
        xSpan <- c(max( stretchX*(min(blobCoordinates$x)-marginX) ,1),
                   min( stretchX*(max(blobCoordinates$x)+marginX) ,width(workingImage$origImg)) )
        ySpan <- c(max( stretchY*(min(blobCoordinates$y-1)-marginY) ,1),
                   min( stretchY*(max(blobCoordinates$y-1)+marginY) ,height(workingImage$origImg)))
        
        if(diff(xSpan) > minXY && diff(ySpan) > minXY)
        {
        save.image(suppressWarnings(as.cimg(workingImage$origImg
                                            [xSpan[1]:xSpan[2],
                                             ySpan[1]:ySpan[2],,]))
                   ,file=file.path(saveDir, paste0(mainImgName,"_",blobInc,".jpg")),1.0)
        }
        unlink( list.files(dirname(tempdir()), pattern = "\\.PPM$|\\.ppm$", full.names = T) )
        gc()
      }
    }
  }
}