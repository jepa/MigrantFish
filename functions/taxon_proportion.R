
# taxon_proportion
# This function is the main analysis estimating the proportion change above historic levels

taxon_proportion <- function(taxon_key, dbem_grid){
  
  print(taxon_key)
  
  stradd_data <- GetResults(taxon_key)
  # category <- unique(stradd_data$cat)
  
  rfmo_areas <- stradd_data %>% 
    pull(rfmo_name) %>% 
    unique()
  
  files_path <-list.files(my_path("G","dbem/dbem_cmip6/r_data"),full.names = T)[-3] # remove GFDL45B
  
  to_read <- paste0(taxon_key,"Abd.RData")
  
  for(m in 1:6){
    # m = 1
    #################################
    # List esm folders
    file_to_read <- paste0(files_path[m],"/",to_read)
    print(file_to_read)
    if(file.exists(file_to_read)){
      
      load(file_to_read)
      
      # Transform it to df--
      
      
      if(exists("sppabdfnl")){
        spp_data <- as.data.frame(sppabdfnl) %>% 
          rowid_to_column("index")
        colnames(spp_data) <- c("index", seq(1951, 2100, 1))
        rm(sppabdfnl) 
      }else{
        spp_data <- as.data.frame(data) %>% 
          rowid_to_column("index")
        colnames(spp_data) <- c("index", seq(1951, 2100, 1))
        rm(data) 
      }
      
      
      # Get area of analysis
      taxon_rfmo_dbem_area <-stradd_data %>%
        pivot_longer(c(realm,rfmo_name)) %>% 
        pull(value) %>% 
        unique()
      
      # Get ammount abundance per region
      spp_data_area <-spp_data %>% 
        gather("year","value",`1951`:`2100`) %>%
        left_join(dbem_grid,
                  by = c("index")
        ) %>% 
        left_join(rfmo_index,
                  by = "index",
                  relationship = "many-to-many") %>% 
        mutate(name = ifelse(is.na(realm),rfmo_name,realm)) %>% 
        filter(name %in% taxon_rfmo_dbem_area) %>%
        group_by(year,name) %>% 
        summarise(total_zone_abd = sum(value,na.rm = T),
                  .groups = "drop") %>% 
        mutate(taxon_key = as.integer(taxon_key))
      
      # Estimate proportions of each region
      
      # RFMO values
      rfmo_values <- spp_data_area %>% 
        filter(name %in% stradd_data$rfmo_name) %>% 
        rename(rfmo_total_zone_abd = total_zone_abd,
               rfmo_name = name) %>% 
        left_join(stradd_data,
                  by = c("rfmo_name","taxon_key"),
                  relationship = "many-to-many") %>% 
        rename(realm_name = realm)
      
      # Realms values
      realm_values <- spp_data_area %>% 
        filter(name %in% stradd_data$realm) %>% 
        rename(realm_total_zone_abd = total_zone_abd,
               realm_name = name)
      
      
      # combine both regions to estimate proportions
      spp_proportion <- left_join(rfmo_values,realm_values,
                                  by = join_by("year", "taxon_key","realm_name")
      ) %>% 
        mutate(region_total = rfmo_total_zone_abd+realm_total_zone_abd) %>% 
        mutate(per_rfmo = rfmo_total_zone_abd/region_total*100) %>%  # done with RFMO 
        filter(region_total >0) # Remove cases where there is no catch data in any area
      
      # How it looks
      # ggplot(spp_proportion) +
      #   geom_area(
      #     aes(
      #       x = as.numeric(year),
      #       y = per_rfmo,
      #       fill = realm
      #       # fill = high_mig_spa
      #     )
      #   ) +
      #   facet_wrap(~rfmo_name)
      
      
      # Estimate changes in abd proportion
      
      # Early proportions
      hs_historical_means <- spp_proportion %>% 
        filter(year <= 2014) %>%
        group_by(taxon_key,rfmo_name,realm_name) %>% 
        summarise(hs_mean = mean(per_rfmo, na.rm = T),
                  hs_sd = sd(per_rfmo, na.rm = T),
                  .groups = "drop") %>%
        mutate(top_tresh = hs_mean+2*hs_sd,
               low_tresh = hs_mean-2*hs_sd) %>% 
        select(-hs_mean,-hs_sd)
      
      # Estimate future proportions that overshoot the mean =- 2 sd
      prop_chng <- spp_proportion %>% 
        mutate(period = ifelse(year >2021 & year <2040,"ear",
                               ifelse(year > 2041 & year <2060,"mid",NA)
        )
        ) %>% 
        filter(!is.na(period)) %>% 
        group_by(taxon_key,rfmo_name,realm_name,area_rfmo,area_realm,period) %>% 
        summarise(mean = mean(per_rfmo, na.rm = T),
                  sd = sd(per_rfmo, na.rm = T),
                  .groups = "drop") %>% 
        left_join(hs_historical_means,
                  by = c("taxon_key","rfmo_name","realm_name"),
                  relationship = "many-to-many") %>% 
        mutate(change = ifelse(mean > top_tresh,"gain",
                               ifelse(mean < low_tresh,"lost","same")
        )
        ) 
      
      
      # Incorporate rcp and esm info to data
      # str_count(files_path[m]) # 90
      
      final_data <- prop_chng %>% 
        mutate(esm = str_to_lower(str_sub(files_path[m],80,83)),
               rcp = paste0("rcp",str_sub(files_path[m],84,85)),
               esm = ifelse(esm == "mpi2","mpi", ifelse(esm == "mpi8","mpi",esm)), # Fix MPI
               rcp = ifelse(rcp == "rcp6F","rcp26", ifelse(rcp == "rcpBF","rcp85",rcp)), # Fix MPS
        ) %>% 
        select(taxon_key,esm,rcp,period,rfmo_name,change,realm_name,low_tresh,mean,top_tresh,area_rfmo,area_realm)
      
      
      if(m == 1){
        final_output <- final_data
      }else{
        final_output <- bind_rows(final_output,final_data)
      }
      
      
    } # Close models for loop
    
  }
  
  # Save file
  name_file <- my_path("R","Per_change_realm_rfmo", paste0(taxon_key,"_perchg.csv"))
  write_csv(final_output, name_file)
  return(paste("Data for",taxon_key, "saved"))
  
}
