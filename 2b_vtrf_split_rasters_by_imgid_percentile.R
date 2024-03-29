library(data.table)
library(terra)

# This script splits local raster by percentile and then writes new rasters
# Creates a dictionary with these paths, percentiles, the imgids, and TripIDs

##############################
# Functions

##############################
# Set directories
pwd <- dirname(rstudioapi::getActiveDocumentContext()$path)
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

repository <- "fishing_footprint_bias_for_wind"
path_base <- "C:/Users/lianne.allen-jacobso/Documents/"
check_pwd <- paste0(path_base, "Repositories/",repository)
pwd == check_pwd

dir_output <- paste0(path_base, "Output/", repository)
dir_data <- paste0(path_base, "Data/", repository)

##############################
# Pull in data
dt_paths_vtrb <- readRDS(paste0(dir_output, "/dt_paths_vtrb.rds"))

##############################
# Split raster by percentile
# create empty data table to add summary data
dt_paths_vtrb_split <- data.table()
unique_imgids <- dt_paths_vtrb$imgid #identify unique imgids for loop
this_imgid <- unique_imgids[[1]]

for (this_imgid in unique_imgids) {
  this_tripid <- dt_paths_vtrb[imgid==this_imgid,tripid] # find tripID for imgid
  this_trip_area <- dt_paths_vtrb[imgid==this_imgid,trip_area] # find tripID for imgid
  this_path <- dt_paths_vtrb[imgid==this_imgid, path] #find local path
  check_path <- file.exists(this_path)
    if(length(check_path) == 0){
      this_warning <- paste("File missing for imgid: ", this_imgid, sep = " ")
      warning(this_warning) #return error if file is missing
      next
    } else if (check_path == TRUE){
      this_rast <- rast(this_path)
      unique_values <- setDT(unique(this_rast)) #select unique cell values in raster
      unique_values <- setNames(unique_values, "values") #rename column
      setorder(unique_values, -values) # reorder values
      # add column identifyiny value by its percentile - assumes that percentiles can be ranked
      # this could be wrong if there are large chunks missing from some percentiles but not others
      # however, a quick look shows the same colors for each buffer, suggesting they can be ranked
      unique_values[, percentile := c("25th", "50th", "75th", "90th", "outsideBuffer")]
      
      # select parts of raster equal to unique values
      raster_25<- this_rast == unique_values[percentile=="25th", values]
      raster_50<- this_rast == unique_values[percentile=="50th", values]
      raster_75<- this_rast == unique_values[percentile=="75th", values]
      raster_90<- this_rast == unique_values[percentile=="90th", values]
      
      # Count the number of cells with each value
      count_25 <- global(this_rast== unique_values[percentile=="25th", values],
                         sum, na.rm=TRUE)
      count_50 <- global(this_rast== unique_values[percentile=="50th", values],
                         sum, na.rm=TRUE)
      count_75 <- global(this_rast== unique_values[percentile=="75th", values],
                         sum, na.rm=TRUE)
      count_90 <- global(this_rast== unique_values[percentile=="90th", values],
                         sum, na.rm=TRUE)
      
      counts <-rbind(count_25, count_50, count_75, count_90)
      counts <- data.table(sum = counts$sum)
      
      # create file names, save rasters
      path_base <- paste0(dir_output, "/vtrbs_split_by_percentile")
      new_path_25 <- paste0(path_base, "/25th_", this_tripid, "_", this_imgid, ".tif")
      writeRaster(raster_25, new_path_25, overwrite=TRUE)
      
      new_path_50 <-  paste0(path_base, "/50th_", this_tripid, "_", this_imgid, ".tif")
      writeRaster(raster_50, new_path_50, overwrite=TRUE)
      
      new_path_75 <-  paste0(path_base, "/75th_", this_tripid, "_", this_imgid, ".tif")
      writeRaster(raster_75, new_path_75, overwrite=TRUE)
      
      new_path_90 <-  paste0(path_base, "/90th_", this_tripid, "_", this_imgid, ".tif")
      writeRaster(raster_90, new_path_90, overwrite=TRUE)
      
      # combine tripID, imgid, percentile, and path into a data table
      these_paths <- data.table(tripid= c(this_tripid, this_tripid, this_tripid, this_tripid),
                                trip_area = c(this_trip_area, this_trip_area, this_trip_area, this_trip_area),
                             imgid=c(this_imgid, this_imgid, this_imgid, this_imgid),
                             percentile=c("25th", "50th", "75th", "90th"),
                             value = unique_values[1:4, values],
                             counts = counts[,sum],
                             paths = c(new_path_25,new_path_50, new_path_75,new_path_90))
      
      dt_paths_vtrb_split <- rbindlist(list(dt_paths_vtrb_split, these_paths))
      
    } else {
      this_warning <- paste("Error with file path,
                            file.exists is not TRUE or FALSE, for imgid: ",
                            this_imgid, sep = " ")
      # Catch all error - not sure why this would happen
      # would require additional exploration
      warning(this_warning) 
    }
}

dt_paths_vtrb_split[, value_lower_3 := ifelse(percentile == "90th", 0, (1/3)/counts)][
  , value_lower_2 := ifelse(percentile %in% c("90th", "75th"), 0, (1/2)/counts)][
    , value_lower_1 := ifelse(percentile %in% c("90th", "75th", "50th"), 0, (1/1)/counts)]

saveRDS(dt_paths_vtrb_split, paste0(dir_output, "/dt_paths_vtrb_split_by_percentile.rds"))
