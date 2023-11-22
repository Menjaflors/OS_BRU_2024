

# SCRIPT NASA GENERIC. IT IS BETTER TO RUN IT OUTSIDE ANY PROJECT!

#https://lpdaac.usgs.gov/resources/e-learning/getting-started-appeears-api-r-area-request/
# Load necessary packages into R                                               
library(getPass)           # A micro-package for reading passwords
library(httr)              # To send a request to the server/receive a response from the server
library(jsonlite)          # Implements a bidirectional mapping between JSON data and the most important R data types
library(geojsonio)         # Convert data from various R classes to 'GeoJSON' 
library(geojsonR)          # Functions for processing GeoJSON objects
library(rgdal)             # Functions for spatial data input/output
library(sp)                # classes and methods for spatial data types
library(raster)            # Classes and methods for raster data
library(rasterVis)         # Advanced plotting functions for raster objects 
library(ggplot2)           # Functions for graphing and mapping
library(RColorBrewer)      # Creates nice color schemes
library(terra)
library(geojsonlint)

## Download data

### DM: LOG IN IN NASA APPEEARS. is it necessary to have a user and a password. #DM: this token will last only 48h.
API_URL = 'https://appeears.earthdatacloud.nasa.gov/api/'  # Set the AppEEARS API to a variable
user <- getPass(msg = "user")        # Enter NASA Earthdata Login Username
password <- getPass(msg = "password")    # Enter NASA Earthdata Login Password
secret <- jsonlite::base64_enc(paste(user, password, sep = ":"))  # Encode the string of username and password

response <- httr::POST(paste0(API_URL,"login"), add_headers("Authorization" = paste("Basic", gsub("/n", "", secret)), # Insert API URL, call login service, set the component of HTTP header, and post the request to the server
                                                            "Content-Type" ="application/x-www-form-urlencoded;charset=UTF-8"), body = "grant_type=client_credentials")

response_content <- content(response)                          # Retrieve the content of the request
token_response <- toJSON(response_content, auto_unbox = TRUE)  # Convert the response to the JSON object
remove(user, password, secret, response)                       # Remove the variables that are not needed anymore 


### DM: Request layers:
Evapo<-"MOD13Q1.061"

EVAPO_req <- GET(paste0(API_URL,"product/", Evapo))  # Request the info of a product from product URL
EVAPO_content <- content(EVAPO_req)                             # Retrieve content of the request 
EVAPO_response <- toJSON(EVAPO_content, auto_unbox = TRUE)      # Convert the content to JSON object
remove(EVAPO_req, EVAPO_content)                                # Remove the variables that are not needed anymore
names(fromJSON(EVAPO_response))                                    # print the layer's names    

desired_layers <- c("_250m_16_days_NDVI" ,"_250m_16_days_EVI")     
desired_prods <- Evapo
layers <- data.frame(product = desired_prods, layer = desired_layers)              

### DM: Create an extent in order to download the data
e <- extent(c(-1.2, 2.9, 41.9, 43.3))
e<-as(e, "SpatialPolygons")
e<-SpatialPolygonsDataFrame(e, data = data.frame(ID = 1))

area_json<-geojsonio::geojson_json(e, geometry = "polygon")
area_json<- geojsonR::FROM_GeoJson(area_json)

### DM: create projection, name, type, date of the task
proj_req <- GET(paste0(API_URL, "spatial/proj"))          # Request the projection info from API_URL            
proj_content <- content(proj_req)                         # Retrieve content of the request
proj_response <- toJSON(proj_content, auto_unbox = TRUE)  # Convert the content to JSON object
remove(proj_req, proj_content)                            # Remove the variables that are not needed 
projs <- fromJSON(proj_response)                          # Read the projects as a R object
projection <- projs[projs$Name=="geographic",]            # Choose the projection for your output

###DM: for EBBA2

taskName <- 'NDVI_PYR'          # Enter name of the task. 
taskType <- 'area'            # Type of task, it can be either "area" or "point"

projection <- projection$Name # Set output projection 
outFormat <- 'geotiff'        # Set output file format type. it can be either 'geotiff' or 'netcdf4'

startDate <- '01-01-2012'     # Start of the date range for which to extract data: MM-DD-YYYY
endDate <- '12-31-2022'       # End of the date range for which to extract data: MM-DD-YYYY
date <- data.frame(startDate = startDate, endDate = endDate)

out <- list(projection )
names(out) <- c("projection")
out$format$type <- outFormat

area_json$features[[1]]$geometry$coordinates <- list(area_json$features[[1]]$geometry$coordinates)

task_info <- list(date, layers, out, area_json)                 # Create a list of data frames 
names(task_info) <- c("dates", "layers", "output", "geo")       # Assign names

task <- list(task_info, taskName, taskType)                     # Create a nested list 
names(task) <- c("params", "task_name", "task_type")            # Assign names  

task_json <- jsonlite::toJSON(task, auto_unbox = TRUE, digits = 10)

token <- paste("Bearer", fromJSON(token_response)$token)     # Save login token to a variable. NECESSARY IF WE CHANGE ID OF DOWNLOAD!


### DM: request to the API task service
response <- POST(paste0(API_URL, "task"), body = task_json , encode = "json", 
                 add_headers(Authorization = token, "Content-Type" = "application/json"))

###DM: Consult status of your request. If you are already logged in in https://appeears.earthdatacloud.nasa.gov/explore, you can find a progress bar.

task_content <- content(response)                                     # Retrieve content of the request 
task_response <- jsonlite::toJSON(task_content, auto_unbox = TRUE)    # Convert the content to JSON and prettify it
prettify(task_response)                                               # Print the task response

#One hour!
filepath<-"../../VARIABLES/DHI/ORIGINAL"

###DM: download your request to your path: 

task_id <- fromJSON(task_response)[[1]]
task_id<-"cbe3ac27-b0c7-4992-94a8-fe43fdb81f1f" #DM: If we consult directly in the web the progress:
response <- GET(paste0(API_URL, "bundle/", task_id), add_headers(Authorization = token))
bundle_response <- prettify(toJSON(content(response), auto_unbox = TRUE))

bundle <- fromJSON(bundle_response)$files
bundle <- bundle[!grepl("Quality|csv|txt|xml|json|README", bundle$file_name), ] #Remove quality layers, statistics, etc. 


for (id in bundle$file_id){
  # retrieve the filename from the file_id
  filename <- bundle[bundle$file_id == id,]$file_name    
  filename <- basename(filename)
  # create a destination directory to store the file in
  suppressWarnings(dir.create(dirname(filepath)))
  # write the file to disk using the destination directory and file name 
  response <- GET(paste0(API_URL, "bundle/", task_id, "/", id), 
                  write_disk(file.path(filepath, filename),overwrite = TRUE), progress(),
                  add_headers(Authorization = token))
}


##MOVE THE ARCHIVES. FIRST, BETWEEN DHI
DHI <- c("EVI", "NDVI")
#folders <- c("EVI_ANYS", "NDVI_ANYS")

source_folder <- "../../VARIABLES/DHI/ORIGINAL"

file_list <- list.files(source_folder, full.names = TRUE)

for (i in DHI) {
  target_string <- i
  
  for (file_path in file_list) {
    if (grepl(target_string, file_path)) {
      j <- ifelse(i == "EVI", "EVI_ANYS", "NDVI_ANYS")
      
      destination_folder <- paste0("../../VARIABLES/DHI/", j)
      
      new_path <- file.path(destination_folder, basename(file_path))
      
      file.copy(file_path, new_path)
      #   file.remove(file_path)
      
      cat("Moved:", basename(file_path), "/n")
    }
  }
  
  cat("Finished moving", i, "files./n")
}




##MOVE THE ARCHIVES, FINALLY, FOR YEARS 
anys<-c("2012","2013","2014","2015","2016","2017","2018","2019","2020","2021","2022")

for (k in DHI) {
  for (i in anys) {
    source_folder <- paste0("../../VARIABLES/DHI/", k,"_anys")
    destination_folder <- paste0("../../VARIABLES/DHI/", k, "/", i)
    
    file_list <- list.files(source_folder, full.names = TRUE)
    target_string <- i
    files_to_move <- character(0)  # Initialize an empty vector to store files for moving
    
    for (file_path in file_list) {
      if (grepl(target_string, file_path)) {
        files_to_move <- c(files_to_move, file_path)  # Add matching files to the vector
      }
    }
    
    # Move and remove files after identifying all matching files
    for (file_path in files_to_move) {
      new_path <- file.path(destination_folder, basename(file_path))
      file.copy(file_path, new_path)
      #    file.remove(file_path)
    }
    
  }
}



#Be careful, in 2017 folder there are some elements that contain the string 2017 but before maybe they contain other years. 
#REMOVE THEM MANUALLY. They must contain 23 archives per DHI/YEAR. 2022, 2019, 2016, 2014 and 2012 also contain 2020 archives. REMOVE!


##CALCULATE VAR, MIN AND ACC FOR NDVI. THEN, DO THE MEAN BETWEEN YEARS
anys <- c(2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022)

acc_NDVI <- list()
min_NDVI <- list()
var_NDVI <- list()

for (j in 1:length(anys)) {
  i <- anys[j]  # Get the current year
  
  dir_NDVI <- paste0("../../VARIABLES/DHI/NDVI/", i)
  filenames <- list.files(dir_NDVI, pattern = "NDVI", full.names = TRUE)
  NDVI <- rast(filenames)
  
  acc <- app(NDVI, fun = "sum", na.rm = TRUE)
  min <- app(NDVI, fun = "min", na.rm = TRUE)
  sd <- app(NDVI, fun = "sd", na.rm = TRUE)
  mean <- app(NDVI, fun= "mean", na.rm=TRUE)
  var<- sd/mean  #We will use the coefficient of variation: sd/mean, like it is used in https://doi.org/10.1016/j.rse.2017.04.018
  
  acc_NDVI[[j]] <- acc
  min_NDVI[[j]] <- min
  var_NDVI[[j]] <- var
}

acc_NDVI<-do.call(c, acc_NDVI)
acc_NDVI<-app(acc_NDVI, fun="mean")

min_NDVI<-do.call(c, min_NDVI)
min_NDVI<-app(min_NDVI, fun="mean")

var_NDVI<-do.call(c, var_NDVI)
var_NDVI<-app(var_NDVI, fun="mean")



##CALCULATE VAR, MIN AND ACC FOR EVI. THEN, DO THE MEAN BETWEEN YEARS
anys <- c(2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022)

acc_EVI <- list()
min_EVI <- list()
var_EVI <- list()

for (j in 1:length(anys)) {
  i <- anys[j]  # Get the current year
  
  dir_EVI <- paste0("../../VARIABLES/DHI/EVI/", i)
  filenames <- list.files(dir_EVI, pattern = "EVI", full.names = TRUE)
  EVI <- rast(filenames)
  
  acc <- app(EVI, fun = "sum", na.rm = TRUE)
  min <- app(EVI, fun = "min", na.rm = TRUE)
  sd <- app(NDVI, fun = "sd", na.rm = TRUE)
  mean <- app(NDVI, fun= "mean", na.rm=TRUE)
  var<- sd/mean  #We will use the coefficient of variation: sd/mean, like it is used in https://doi.org/10.1016/j.rse.2017.04.018
  
  acc_EVI[[j]] <- acc
  min_EVI[[j]] <- min
  var_EVI[[j]] <- var
}

acc_EVI<-do.call(c, acc_EVI)
acc_EVI<-app(acc_EVI, fun="mean")

min_EVI<-do.call(c, min_EVI)
min_EVI<-app(min_EVI, fun="mean")

var_EVI<-do.call(c, var_EVI)
var_EVI<-app(var_EVI, fun="mean")

writeRaster(acc_NDVI, "../../VARIABLES/DHI/acc_NDVI.tif", overwrite=T)
writeRaster(min_NDVI, "../../VARIABLES/DHI/min_NDVI.tif", overwrite=T)
writeRaster(var_NDVI, "../../VARIABLES/DHI/var_NDVI.tif", overwrite=T)

writeRaster(acc_EVI, "../../VARIABLES/DHI/acc_EVI.tif", overwrite=T)
writeRaster(min_EVI, "../../VARIABLES/DHI/min_EVI.tif", overwrite=T)
writeRaster(var_EVI, "../../VARIABLES/DHI/var_EVI.tif", overwrite=T)

