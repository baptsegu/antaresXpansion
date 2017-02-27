#' Set ANTARES study options related to the current benders decomposition
#' 
#' 
#' @param benders_options
#'   list of benders decomposition options, as returned by
#'   \code{\link{read_options}}.
#' @param opts
#'   list of simulation parameters returned by the function
#'   \code{antaresRead::setSimulationPath}
#'
#' @return nothing
#' 
#' @import antaresRead assertthat
#' @export
set_antares_options <- function(benders_options, opts = simOptions())
{
  # 1 - set output filtering options
  enable_custom_filtering(TRUE, opts)
  enable_year_by_year(TRUE, opts)
  filter_output_areas(areas = getAreas(opts = opts), filter = c("weekly", "annual"), type = c("year-by-year", "synthesis"), opts = opts)
  filter_output_links(links = getLinks(opts = opts), filter = c("weekly", "annual"), type = c("year-by-year", "synthesis"), opts = opts)
  
  # 2 - set unit-commitment mode
  if(benders_options$uc_type == "accurate")
  {
    set_uc_mode(mode = "accurate", opts = opts)
    enable_uc_heuristic(enable = TRUE, opts = opts)
  }
  if(benders_options$uc_type == "fast")
  {
    set_uc_mode(mode = "fast", opts = opts)
    enable_uc_heuristic(enable = TRUE, opts = opts)
  }
  if(benders_options$uc_type == "relaxed_fast")
  {
    set_uc_mode(mode = "fast", opts = opts)
    enable_uc_heuristic(enable = FALSE, opts = opts)
  }
  
  # 3 - set week and initial day
  #    we need to ensure the consistency between the weekly optimisation and the weekly
  #    aggregation of the output
  
  month_name <- c("january", "december", "november", "october", "september", "august", "july", "june", "may", "april", "march", "february")
  day_per_month <- c(0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 28)
  
  day_name <- c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
  if (opts$parameters$general$leapyear)
  {
    day_per_month[12] <- 29
  }
  month_id <- which(month_name == opts$parameters$general$"first-month-in-year")
  assert_that(length(month_id) == 1)
  n_day <- (-sum(day_per_month[1:month_id]) + opts$parameters$general$simulation.start - 1) %% 7
  
  first_day_week <- day_name[((which(day_name == opts$parameters$general$january.1st) + n_day - 1) %% 7 ) +1]
  set_week(first_day = first_day_week, opts)
}


#' Update costs and rentability files of the average cuts
#' Create files in_avgrentability.txt and in_avgcuts.txt which
#' will be later read by AMPL as input of the master problem
#' 
#' 
#' @param current_it
#'   list of current iteration characteristics
#' @param candidates
#'   list of investment candidates, as returned by
#'   \code{\link{read_candidates}}
#' @param output_link_s
#'   antaresDataList of all the links of the study with a yearly time step
#'   and averaged on all MC years
#' @param ov_cost
#'   overall costs of this iteration
#' @param n_w
#'   number of weeks per year
#' @param tmp_folder
#'   temporary folder in which to write the files
#'   
#' @return nothing
#' 
#' @import antaresRead
#' 
update_average_cuts <- function(current_it, candidates, output_link_s, ov_cost, n_w, tmp_folder)
{
  n_candidates <- length(candidates)
  
  #write in_avgcuts.txt file 
  script  <-  paste0(current_it$id, " ", ov_cost)
  write(script, file = paste0(tmp_folder, "/in_avgcuts.txt"), append = TRUE )      
  
  # write in_avgrentability.txt file
  script  <-  ""
  for (c in 1:n_candidates)
  {
    tmp_rentability <- sum(as.numeric(subset(output_link_s, link == candidates[[c]]$link)$"MARG. COST")) - candidates[[c]]$cost * n_w / 52
    script <- paste0(script, current_it$id, " ", candidates[[c]]$name, " ", tmp_rentability)
    if (c != n_candidates) { script <- paste0(script, "\n")}
  }
  write(script, file = paste0(tmp_folder, "/in_avgrentability.txt"), append = TRUE )
}

#' Update costs and rentability files of the yearly cuts
#' Create files in_yearlyrentability.txt and in_yearlycuts.txt which
#' will be later read by AMPL as input of the master problem
#' 
#' 
#' @param current_it
#'   list of current iteration characteristics
#' @param candidates
#'   list of investment candidates, as returned by
#'   \code{\link{read_candidates}}
#' @param output_area_y
#'   antaresDataList of all the areas of the study with a yearly time step
#' @param output_link_y
#'   antaresDataList of all the links of the study with a yearly time step
#' @param inv_cost
#'   investments costs of this iteration
#' @param n_w
#'   number of weeks per year
#' @param tmp_folder
#'   temporary folder in which to write the files

#'   
#' @return nothing
#' 
#' @import antaresRead
#' 
update_yearly_cuts <- function(current_it,candidates, output_area_y, output_link_y, inv_cost, n_w, tmp_folder)
{
  # compute a few intermediate variables
  n_candidates <- length(candidates)
  last_y <- current_it$mc_years[length(current_it$mc_years)]
  
  # initiate scripts
  script_rentability  <-  ""
  script_cost <- ""
  
  # for every mc years and every week
  for(y in current_it$mc_years)
  {
    script_cost <- paste0(script_cost, current_it$id, " ", y , " ",
                          sum(as.numeric(subset(output_area_y, mcYear == y)$"OV. COST")) +
                            sum(as.numeric(subset(output_link_y, mcYear == y)$"HURDLE COST")) +
                            inv_cost)
    if (y != last_y) {script_cost <- paste0(script_cost, "\n")}
    
    for(c in 1:n_candidates)
    {
      tmp_rentability <- sum(as.numeric(subset(output_link_y, link == candidates[[c]]$link & mcYear == y)$"MARG. COST")) - candidates[[c]]$cost * n_w / 52
      
      script_rentability <- paste0(script_rentability, current_it$id, " ", y, " ", candidates[[c]]$name, " ", tmp_rentability)
      if (c != n_candidates || y != last_y)
      {
        script_rentability <- paste0(script_rentability, "\n")
      }
    }
  }
  write(script_rentability, file = paste0(tmp_folder, "/in_yearlyrentability.txt"), append = TRUE )
  write(script_cost, file = paste0(tmp_folder, "/in_yearlycuts.txt"), append = TRUE )
}



#' Update costs and rentability files of the weekly cuts
#' Create files in_weeklyrentability.txt and in_weeklycuts.txt which
#' will be later read by AMPL as input of the master problem
#' 
#' 
#' @param current_it
#' list of current iteration characteristics
#' @param candidates
#'   list of investment candidates, as returned by
#'   \code{\link{read_candidates}}
#' @param output_area_w
#'   antaresDataList of all the areas of the study with a weekly time step
#' @param output_link_w
#'   antaresDataList of all the links of the study with a weekly time step
#' @param inv_cost
#'   investments costs of this iteration
#' @param tmp_folder
#'   temporary folder in which to write the files
#'   
#' @return nothing
#' 
#' @import antaresRead
#' 
update_weekly_cuts <- function(current_it, candidates, output_area_w, output_link_w, inv_cost, tmp_folder)
{
  
  # compute a few intermediate variables
  n_candidates <- length(candidates)
  last_w <- current_it$weeks[length(current_it$weeks)]
  last_y <- current_it$mc_years[length(current_it$mc_years)]
  
  # initiate scripts
  script_rentability  <-  ""
  script_cost <- ""

  # for every mc years and every week
  for(y in current_it$mc_years)
  {
    for(w in current_it$weeks)
      
    {
      script_cost <- paste0(script_cost, current_it$id, " ", y , " ", w, " ", 
                            sum(as.numeric(subset(output_area_w, mcYear == y & timeId == w)$"OV. COST")) +
                            sum(as.numeric(subset(output_link_w, mcYear == y & timeId == w)$"HURDLE COST")) +
                            inv_cost/52)
      if (y != last_y || w != last_w) {script_cost <- paste0(script_cost, "\n")}
      
      
      for(c in 1:n_candidates)
      {
        tmp_rentability <- sum(as.numeric(subset(output_link_w, link == candidates[[c]]$link & mcYear == y & timeId == w)$"MARG. COST")) - candidates[[c]]$cost /52

        script_rentability <- paste0(script_rentability, current_it$id, " ", y , " ", w , " ", candidates[[c]]$name, " ", tmp_rentability)
        
        if (c != n_candidates || y != last_y || w != last_w)
        {
          script_rentability <- paste0(script_rentability, "\n")
        }
      }
    }
  }
  write(script_rentability, file = paste0(tmp_folder, "/in_weeklyrentability.txt"), append = TRUE )
  write(script_cost, file = paste0(tmp_folder, "/in_weeklycuts.txt"), append = TRUE )
}