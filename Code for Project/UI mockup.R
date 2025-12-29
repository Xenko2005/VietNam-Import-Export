# ====== Phần 1: Chạy Model ======
if (!requireNamespace("prophet", quietly = TRUE)) install.packages("prophet")
if (!requireNamespace("tidyverse", quietly = TRUE)) install.packages("tidyverse")
if (!requireNamespace("lubridate", quietly = TRUE)) install.packages("lubridate")
if (!requireNamespace("zoo", quietly = TRUE)) install.packages("zoo")

library(tidyverse)
library(prophet)
library(lubridate)
library(scales)
library(zoo)

#Import Dataset
data_raw_path  <- "D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged_summary.csv"
data_2025_path <- "D:\\Download\\Data for subject\\DSR_cleaned\\Im05-2025-6_clean.csv"
target_name    <- "Ukraine"    # đổi nếu cần
auto_log_check <- TRUE

#Đọc dữ liệu
data_raw_all <- read_csv(data_raw_path, show_col_types = FALSE)
data_2025    <- read_csv(data_2025_path, show_col_types = FALSE)

#Chuẩn bị actual 2025
actual_df <- data_2025 %>%
  filter(Names == target_name, is.na(Group)) %>%
  pivot_longer(cols = ends_with("_Value"), names_to = "Month", values_to = "actual") %>%
  mutate(
    Month = str_replace(Month, "_Value", ""),
    Month = str_to_title(Month),
    month_num = match(Month, month.name),
    ds = as.Date(paste(2025, month_num, "01", sep = "-"), format = "%Y-%m-%d"),
    actual = as.numeric(actual)
  ) %>%
  select(ds, actual) %>%
  arrange(ds)

#Chuẩn bị train 2022-2024
train_df <- data_raw_all %>%
  filter(Names == target_name, Group == "Summary", Year >= 2022 & Year <= 2024) %>%
  pivot_longer(cols = ends_with("_Value"), names_to = "Month", values_to = "y") %>%
  mutate(
    Month = str_replace(Month, "_Value", ""),
    Month = str_to_title(Month),
    month_num = match(Month, month.name),
    ds = as.Date(paste0(Year, "-", month_num, "-01"), format = "%Y-%m-%d"),
    y = as.numeric(y)
  ) %>%
  group_by(ds) %>%
  summarise(y = sum(y, na.rm = TRUE), .groups = "drop") %>%
  arrange(ds) %>%
  filter(!is.na(ds))

cat("Train rows:", nrow(train_df), "from", min(train_df$ds), "to", max(train_df$ds), "\n")

#Tiền xử lý missing/zeros/outliers
if (any(is.na(train_df$y))) {
  train_df$y <- na.approx(train_df$y, na.rm = FALSE)
  train_df$y <- na.locf(train_df$y, na.rm = FALSE)
  train_df$y <- na.locf(train_df$y, fromLast = TRUE)
}
if (any(is.na(train_df$y))) train_df$y[is.na(train_df$y)] <- median(train_df$y, na.rm = TRUE)

#Tự động log-transform nếu cần
need_log <- FALSE
if (auto_log_check) {
  n <- nrow(train_df)
  if (n >= 6) {
    half <- floor(n/2)
    v1 <- var(train_df$y[1:half], na.rm = TRUE)
    v2 <- var(train_df$y[(half+1):n], na.rm = TRUE)
    mean1 <- mean(train_df$y[1:half], na.rm = TRUE)
    mean2 <- mean(train_df$y[(half+1):n], na.rm = TRUE)
    if (!is.na(v1) && !is.na(v2) && mean2 > mean1 && v2 > v1*1.5) need_log <- TRUE
  }
  cat("Auto-log decision:", need_log, "\n")
}

if (need_log) {
  min_pos <- min(train_df$y[train_df$y > 0], na.rm = TRUE)
  if (!is.finite(min_pos)) min_pos <- 1
  train_df$y[train_df$y <= 0] <- min_pos * 0.01
}

#Thêm biến tháng
make_month_regressors <- function(df) {
  df2 <- df %>% mutate(m = month(ds))
  for (m in 1:12) df2[[paste0("m_", m)]] <- as.integer(df2$m == m)
  df2 %>% select(-m)
}
train_reg <- make_month_regressors(train_df)
regressor_names <- paste0("m_", 1:12)

#Chuẩn bị dữ liệu cho Prophet
prophet_train <- train_reg %>% select(ds, y, all_of(regressor_names))
if (need_log) prophet_train <- prophet_train %>% mutate(y = log1p(y))

#Baseline Prophet
m_base <- prophet(
  growth = "linear",
  yearly.seasonality = TRUE,
  weekly.seasonality = FALSE,
  daily.seasonality = FALSE,
  changepoint.prior.scale = 0.05,
  interval.width = 0.95
)
m_base <- fit.prophet(m_base, prophet_train %>% select(ds, y))

#Tuned Prophet: Grid Search cho cps & sps và hiển thị kết quả
best_cps <- 0.1
best_sps <- 10
best_mape <- Inf
grid_results <- data.frame(cps = numeric(), sps = numeric(), MAPE = numeric())

if (nrow(prophet_train) > 24) {
  cps_grid <- c(0.001, 0.005, 0.01, 0.05, 0.1, 0.5)
  sps_grid <- c(0.1, 0.5, 1, 5, 10, 20)
  
  # <<-- THAY ĐỔI DUY NHẤT Ở ĐÂY -->>
  if (target_name == "Ukraine") {
    hold_months <- 12
  } else {
    hold_months <- 6
  }
  # <<-- KẾT THÚC THAY ĐỔI -->>
  
  cutoff <- max(prophet_train$ds) %m-% months(hold_months)
  train_cv <- prophet_train %>% filter(ds <= cutoff)
  val_cv   <- prophet_train %>% filter(ds > cutoff)
  
  for (cps in cps_grid) {
    for (sps in sps_grid) {
      cat("Thử cps =", cps, "sps =", sps, "... ")
      
      mtmp <- prophet(
        growth = "linear",
        yearly.seasonality = TRUE,
        seasonality.mode = "additive",
        changepoint.prior.scale = cps,
        seasonality.prior.scale = sps,
        interval.width = 0.95
      )
      
      
      mtmp <- fit.prophet(mtmp, train_cv)
      fut_cv <- val_cv %>% select(ds, all_of(regressor_names))
      pred_cv <- predict(mtmp, fut_cv)
      ytrue <- val_cv$y
      yhat  <- pred_cv$yhat
      if (need_log) { ytrue <- expm1(ytrue); yhat <- pmax(expm1(yhat), 0) }
      mask <- !is.na(ytrue) & ytrue != 0
      mape_cv <- mean(abs((ytrue[mask] - yhat[mask]) / ytrue[mask])) * 100
      
      #Lưu lại kết quả
      grid_results <- rbind(grid_results, data.frame(cps = cps, sps = sps, MAPE = mape_cv))
      
      cat("MAPE =", round(mape_cv, 2), "%\n")
      
      if (mape_cv < best_mape) {
        best_mape <- mape_cv
        best_cps <- cps
        best_sps <- sps
      }
    }
  }
  
  cat("\n===== KẾT QUẢ GRID SEARCH =====\n")
  print(grid_results %>% arrange(MAPE))
  cat("\n=> Best combination: cps =", best_cps, "| sps =", best_sps, "| MAPE =", round(best_mape, 2), "%\n")
}

m_tuned <- prophet(
  growth = "linear",
  yearly.seasonality = TRUE,
  weekly.seasonality = FALSE,
  daily.seasonality = FALSE,
  seasonality.mode = "additive",
  changepoint.range = 0.8,  
  changepoint.prior.scale = best_cps,
  seasonality.prior.scale = best_sps, 
  interval.width = 0.95
)
for (r in regressor_names) m_tuned <- add_regressor(m_tuned, r, standardize = TRUE)
m_tuned <- fit.prophet(m_tuned, prophet_train %>% select(ds, y, all_of(regressor_names)))

#Dự báo 12 tháng (2025)
future_base <- make_future_dataframe(m_base, periods = 12, freq = "month")
pred_base <- predict(m_base, future_base) %>% select(ds, yhat, yhat_lower, yhat_upper)

future_tuned <- make_future_dataframe(m_tuned, periods = 12, freq = "month") %>%
  mutate(month = month(ds))
for (m in 1:12) future_tuned[[paste0("m_", m)]] <- as.integer(month(future_tuned$ds)==m)
pred_tuned <- predict(m_tuned, future_tuned) %>% select(ds, yhat, yhat_lower, yhat_upper)

#Back-transform nếu log
if (need_log) {
  pred_base <- pred_base %>% mutate(yhat = expm1(yhat), yhat_lower = expm1(yhat_lower), yhat_upper = expm1(yhat_upper))
  pred_tuned<- pred_tuned%>% mutate(yhat = expm1(yhat), yhat_lower = expm1(yhat_lower), yhat_upper = expm1(yhat_upper))
}

#Đánh giá với actual 2025
cmp_base <- pred_base %>% left_join(actual_df, by="ds") %>% filter(year(ds)==2025)
cmp_tuned<- pred_tuned %>% left_join(actual_df, by="ds") %>% filter(year(ds)==2025)

calc_metrics <- function(df) {
  df2 <- df %>% drop_na(actual)
  if (nrow(df2)==0) return(list(MAPE=NA, RMSE=NA))
  mape <- mean(abs((df2$actual - df2$yhat)/df2$actual))*100
  rmse <- sqrt(mean((df2$actual - df2$yhat)^2))
  list(MAPE=mape, RMSE=rmse)
}

m1 <- calc_metrics(cmp_base)
m2 <- calc_metrics(cmp_tuned)

cat("\n===== KẾT QUẢ CHO", target_name, "=====\n")
cat("Baseline Prophet : MAPE =", round(m1$MAPE,2), "% | RMSE =", round(m1$RMSE,2), "\n")
cat("Tuned Prophet    : MAPE =", round(m2$MAPE,2), "% | RMSE =", round(m2$RMSE,2), "\n")

#Vẽ biểu đồ
compare_df <- cmp_tuned %>% select(ds, actual, yhat, yhat_lower, yhat_upper)

ggplot(compare_df, aes(x = ds)) +
  geom_ribbon(aes(ymin = yhat_lower, ymax = yhat_upper), fill = "lightblue", alpha = 0.3) +
  geom_line(aes(y = yhat, color = "Dự báo Prophet (tuned)"), size = 1.2) +
  geom_point(aes(y = actual, color = "Thực tế"), size = 2.5) +
  geom_line(aes(y = actual, color = "Thực tế"), linetype = "dashed", size = 1.1) +
  geom_text(aes(y = actual, label = comma(round(actual, 0))),
            vjust = -0.8, size = 3) +
  scale_color_manual(values = c("Dự báo Prophet (tuned)" = "blue", "Thực tế" = "red")) +
  scale_y_continuous(labels = scales::comma) + 
  labs(
    title = paste("So sánh Dự báo Prophet và Dữ liệu Thực tế –", target_name, "(2025)"),
    x = "Tháng",
    y = "Giá trị xuất khẩu (VND)",
    color = ""
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "top")







################################################################################









#Phần 2: UI mockup
required_pkgs <- c("shiny", "prophet", "tidyverse", "lubridate", "zoo", "scales", "DT")
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, repos = "https://cloud.r-project.org")
}

library(shiny)
library(tidyverse)
library(prophet)
library(lubridate)
library(zoo)
library(scales)
library(DT) 

#UI
ui <- fluidPage(
  titlePanel("Dashboard Prophet Forecast"),
  sidebarLayout(
    sidebarPanel(
      textInput("data_raw_path", "Path to Dataset:",
                value = "D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged_summary.csv"),
      
      textInput("data_2025_path", "Path to Actuals:",
                value = "D:\\Download\\Data for subject\\DSR_cleaned\\Im05-2025-6_clean.csv"),
      
      textInput("country", "Country / Region:", value = "EU"),
      
      
      h5("Quick Select:"),
      flowLayout(
        actionButton("btn_eu", "EU"),
        actionButton("btn_asean", "ASEAN"),
        actionButton("btn_us", "United States"),
        actionButton("btn_jp", "Japan"),
        actionButton("btn_kr", "Korea"),
        actionButton("btn_au", "Australia"),
        actionButton("btn_in", "India"),
        actionButton("btn_ua", "Ukraine"),
        actionButton("btn_cn", "China") 
      ),
      hr(),
      
      sliderInput("horizon_months", "Forecast horizon (months):", min = 1, max = 12, value = 12),
      actionButton("run_btn", "Run model"),
      hr(),
      verbatimTextOutput("status"),
      
      hr(),
      h5("Result Metrics:"), 
      verbatimTextOutput("best_metrics_ui") 
      
    ),
    mainPanel(
      tabsetPanel(
        id = "main_tabs",
        tabPanel("Forecast", 
                 plotOutput("plot_forecast_only", height = "500px")
        ),
        tabPanel("Forecast vs Actual", 
                 plotOutput("plot_forecast_actual", height = "500px")
        ),
        tabPanel("Baseline, Actual & Forecast", 
                 plotOutput("plot_baseline_actual", height = "500px")
        )
      )
    )
  )
)

#Server 
server <- function(input, output, session) {
  rv <- reactiveValues(grid = NULL, cmp_all = NULL) 
  
  #THÊM OBSERVERS CHO CÁC NÚT
  observeEvent(input$btn_eu, { updateTextInput(session, "country", value = "EU") })
  observeEvent(input$btn_asean, { updateTextInput(session, "country", value = "ASEAN") })
  observeEvent(input$btn_us, { updateTextInput(session, "country", value = "United States") })
  observeEvent(input$btn_jp, { updateTextInput(session, "country", value = "Japan") })
  observeEvent(input$btn_kr, { updateTextInput(session, "country", value = "Korea") })
  observeEvent(input$btn_au, { updateTextInput(session, "country", value = "Australia") })
  observeEvent(input$btn_in, { updateTextInput(session, "country", value = "India") })
  observeEvent(input$btn_ua, { updateTextInput(session, "country", value = "Ukraine") })
  observeEvent(input$btn_cn, { updateTextInput(session, "country", value = "China, PR") }) # Value là "China, PR"
  
  
  observeEvent(input$run_btn, {
    
    rv$grid <- NULL; rv$cmp_all <- NULL 
    output$status <- renderText("Loading data and running... please wait")
    
    output$best_metrics_ui <- renderText({ "" }) 
    
    # read inputs
    data_raw_path   <- input$data_raw_path
    data_2025_path  <- input$data_2025_path
    target_name     <- input$country
    # auto_log_check <- input$auto_log_check
    forecast_months <- input$horizon_months
    
    # Safe read files
    data_raw_all <- NULL
    data_2025 <- NULL
    
    tryCatch({
      data_raw_all <- read_csv(data_raw_path, show_col_types = FALSE)
    }, error = function(e) {
      output$status <- renderText(paste("ERROR reading data_raw file:", conditionMessage(e)))
      return(NULL)
    })
    
    tryCatch({
      data_2025 <- read_csv(data_2025_path, show_col_types = FALSE)
    }, error = function(e) {
      cat("Note: Could not read 2025 actuals file. 'vs Actual' tab will be empty.\n", conditionMessage(e), "\n")
    })
    
    #CHUẨN BỊ actual_df
    actual_df <- tibble(ds = as.Date(character()), actual = numeric()) 
    if (!is.null(data_2025)) {
      tryCatch({
        actual_df <- data_2025 %>%
          filter(Names == target_name, is.na(Group)) %>%
          pivot_longer(cols = ends_with("_Value"), names_to = "Month", values_to = "actual") %>%
          mutate(
            Month = str_replace(Month, "_Value", ""),
            Month = str_to_title(Month),
            month_num = match(Month, month.name),
            ds = as.Date(paste(2025, month_num, "01", sep = "-"), format = "%Y-%m-%d"), 
            actual = as.numeric(actual)
          ) %>%
          select(ds, actual) %>%
          arrange(ds) %>%
          filter(!is.na(ds))
      }, error = function(e) {
        cat("Error processing actual_df:", conditionMessage(e), "\n")
      })
    }
    
    #Prepare train 2022-2024
    train_df <- data_raw_all %>%
      filter(Names == target_name, Group == "Summary", Year >= 2022 & Year <= 2024) %>%
      pivot_longer(cols = ends_with("_Value"), names_to = "Month", values_to = "y") %>%
      mutate(
        Month = str_replace(Month, "_Value", ""),
        Month = str_to_title(Month),
        month_num = match(Month, month.name),
        ds = as.Date(paste0(Year, "-", month_num, "-01"), format = "%Y-%m-%d"),
        y = as.numeric(y)
      ) %>%
      group_by(ds) %>%
      summarise(y = sum(y, na.rm = TRUE), .groups = "drop") %>%
      arrange(ds) %>%
      filter(!is.na(ds))
    
    if (nrow(train_df) == 0) {
      output$status <- renderText("No training rows found for the selected target_name.")
      return(NULL)
    }
    
    #Missing / zeros imputation
    if (any(is.na(train_df$y))) {
      train_df$y <- na.approx(train_df$y, na.rm = FALSE)
      train_df$y <- na.locf(train_df$y, na.rm = FALSE)
      train_df$y <- na.locf(train_df$y, fromLast = TRUE)
    }
    if (any(is.na(train_df$y))) train_df$y[is.na(train_df$y)] <- median(train_df$y, na.rm = TRUE)
    
    #Auto log-transform decision
    need_log <- FALSE
    if (need_log) {
      min_pos <- min(train_df$y[train_df$y > 0], na.rm = TRUE)
      if (!is.finite(min_pos)) min_pos <- 1
      train_df$y[train_df$y <= 0] <- min_pos * 0.01
    }
    
    #Month regressors
    make_month_regressors <- function(df) {
      df2 <- df %>% mutate(m = month(ds))
      for (m in 1:12) df2[[paste0("m_", m)]] <- as.integer(df2$m == m)
      df2 %>% select(-m)
    }
    train_reg <- make_month_regressors(train_df)
    regressor_names <- paste0("m_", 1:12)
    
    #Prophet train data
    prophet_train <- train_reg %>% select(ds, y, all_of(regressor_names))
    if (need_log) prophet_train <- prophet_train %>% mutate(y = log1p(y))
    
    last_train_date <- max(prophet_train$ds) 
    
    #Baseline fit
    m_base <- prophet(
      growth = "linear",
      yearly.seasonality = TRUE,
      weekly.seasonality = FALSE,
      daily.seasonality = FALSE,
      changepoint.prior.scale = 0.05,
      interval.width = 0.95
    )
    tryCatch({
      m_base <- fit.prophet(m_base, prophet_train %>% select(ds, y)) 
    }, error = function(e) {
      output$status <- renderText(paste("Baseline fit error:", conditionMessage(e)))
      return(NULL)
    })
    
    #9)Grid search
    best_cps <- 0.1; best_sps <- 10; best_mape <- Inf; best_rmse <- Inf 
    base_mape_val <- NA
    base_rmse_val <- NA
    grid_results <- data.frame(cps = numeric(), sps = numeric(), MAPE = numeric(), RMSE = numeric())
    
    if (nrow(prophet_train) > 24) {
      cps_grid <- c(0.001, 0.005, 0.01, 0.05, 0.1, 0.5)
      sps_grid <- c(0.1, 0.5, 1, 5, 10, 20)
      
      if (target_name == "Ukraine") {
        hold_months <- 12
        cat("Using hold_months = 12 (for Ukraine)\n")
      } else {
        hold_months <- 6
        cat("Using hold_months = 6 (for", target_name, ")\n")
      }
      
      if (nrow(prophet_train) <= hold_months) {
        output$status <- renderText(paste("Not enough data for", hold_months, "month validation."))
        return(NULL)
      }
      
      cutoff <- max(prophet_train$ds) %m-% months(hold_months)
      train_cv <- prophet_train %>% filter(ds <= cutoff)
      val_cv   <- prophet_train %>% filter(ds > cutoff)
      
      # Tính metrics baseline
      cat("Calculating baseline metrics on validation set...\n")
      tryCatch({
        fut_cv_base <- val_cv %>% select(ds) 
        pred_cv_base <- predict(m_base, fut_cv_base)
        ytrue_base <- val_cv$y
        yhat_base  <- pred_cv_base$yhat
        if (need_log) { ytrue_base <- expm1(ytrue_base); yhat_base <- pmax(expm1(yhat_base), 0) }
        
        mask_mape_base <- !is.na(ytrue_base) & ytrue_base != 0 
        mask_rmse_base <- !is.na(ytrue_base)             
        
        if (sum(mask_mape_base) > 0) {
          base_mape_val <- mean(abs((ytrue_base[mask_mape_base] - yhat_base[mask_mape_base]) / ytrue_base[mask_mape_base])) * 100
        }
        if (sum(mask_rmse_base) > 0) {
          base_rmse_val <- sqrt(mean((ytrue_base[mask_rmse_base] - yhat_base[mask_rmse_base])^2))
        }
        cat("  Base MAPE =", round(base_mape_val, 2), "% | Base RMSE =", round(base_rmse_val, 2), "\n")
      }, error = function(e) {
        cat("  Error calculating baseline metrics:", conditionMessage(e), "\n")
      })
      
      
      # Bắt đầu vòng lặp Grid search
      for (cps in cps_grid) {
        for (sps in sps_grid) {
          cat("Trying cps =", cps, "sps =", sps, "...\n")
          mtmp <- prophet(
            growth = "linear",
            yearly.seasonality = TRUE,
            seasonality.mode = "additive",
            changepoint.prior.scale = cps,
            seasonality.prior.scale = sps,
            interval.width = 0.95
          )
          
          
          fit_ok <- TRUE
          tryCatch({
            mtmp <- fit.prophet(mtmp, train_cv %>% select(ds, y)) 
          }, error = function(e) {
            fit_ok <<- FALSE
            cat("  -> fit failed:", conditionMessage(e), "\n")
          })
          if (!fit_ok) {
            grid_results <- rbind(grid_results, data.frame(cps=cps, sps=sps, MAPE=NA, RMSE=NA))
            next
          }
          
          # Predict mtmp
          fut_cv <- val_cv %>% select(ds, all_of(regressor_names)) 
          pred_cv <- predict(mtmp, fut_cv)
          ytrue <- val_cv$y
          yhat  <- pred_cv$yhat
          if (need_log) { ytrue <- expm1(ytrue); yhat <- pmax(expm1(yhat), 0) }
          
          mape_cv <- NA
          rmse_cv <- NA
          mask <- !is.na(ytrue) & ytrue != 0 
          
          if (sum(mask) > 0) {
            mape_cv <- mean(abs((ytrue[mask] - yhat[mask]) / ytrue[mask])) * 100
            rmse_cv <- sqrt(mean((ytrue[mask] - yhat[mask])^2)) 
          }
          
          grid_results <- rbind(grid_results, data.frame(cps = cps, sps = sps, MAPE = mape_cv, RMSE = rmse_cv))
          
          if (!is.na(mape_cv) && mape_cv < best_mape) {
            best_mape <- mape_cv
            best_rmse <- rmse_cv 
            best_cps <- cps
            best_sps <- sps
          }
          cat("  MAPE =", round(mape_cv, 2), "% | RMSE =", round(rmse_cv, 2), "\n")
        }
      }
    }
    
    rv$grid <- grid_results
    
    #Fit final tuned model
    m_tuned <- prophet(
      growth = "linear",
      yearly.seasonality = TRUE,
      weekly.seasonality = FALSE,
      daily.seasonality = FALSE,
      seasonality.mode = "additive",
      changepoint.range = 0.8,
      changepoint.prior.scale = best_cps,
      seasonality.prior.scale = best_sps,
      interval.width = 0.95
    )
    for (r in regressor_names) m_tuned <- add_regressor(m_tuned, r, standardize = TRUE)
    tryCatch({
      m_tuned <- fit.prophet(m_tuned, prophet_train %>% select(ds, y, all_of(regressor_names)))
    }, error = function(e) {
      output$status <- renderText(paste("Final fit error:", conditionMessage(e)))
      return(NULL)
    })
    
    #PREDICT
    #Forecast horizon
    future_tuned <- make_future_dataframe(m_tuned, periods = forecast_months, freq = "month") %>%
      mutate(month = month(ds))
    for (m in 1:12) future_tuned[[paste0("m_", m)]] <- as.integer(month(future_tuned$ds) == m)
    
    pred_tuned <- predict(m_tuned, future_tuned) %>% 
      select(ds, 
             yhat_tuned = yhat, 
             yhat_lower_tuned = yhat_lower, 
             yhat_upper_tuned = yhat_upper) 
    
    if (need_log) {
      pred_tuned <- pred_tuned %>%
        mutate(yhat_tuned = pmax(expm1(yhat_tuned), 0),
               yhat_lower_tuned = pmax(expm1(yhat_lower_tuned), 0),
               yhat_upper_tuned = pmax(expm1(yhat_upper_tuned), 0))
    }
    
    #Baseline forecast
    future_base <- make_future_dataframe(m_base, periods = forecast_months, freq = "month")
    
    pred_base <- predict(m_base, future_base) %>% 
      select(ds, 
             yhat_base = yhat, 
             yhat_lower_base = yhat_lower, 
             yhat_upper_base = yhat_upper) 
    
    if (need_log) {
      pred_base <- pred_base %>%
        mutate(yhat_base = pmax(expm1(yhat_base), 0),
               yhat_lower_base = pmax(expm1(yhat_lower_base), 0),
               yhat_upper_base = pmax(expm1(yhat_upper_base), 0))
    }
    
    
    #TẠO DỮ LIỆU & HIỂN THỊ METRICS
    
    rv$cmp_all <- pred_tuned %>%
      full_join(pred_base, by = "ds") %>%
      full_join(train_df %>% select(ds, y_hist = y), by = "ds") %>%
      full_join(actual_df, by = "ds") %>%
      arrange(ds)
    
    #Tính toán metrics 2025
    cmp_base_2025 <- rv$cmp_all %>% filter(year(ds)==2025)
    cmp_tuned_2025 <- rv$cmp_all %>% filter(year(ds)==2025)
    
    calc_metrics_2025 <- function(df, yhat_col_name) {
      df2 <- df %>% drop_na(actual)
      if (nrow(df2)==0) return(list(MAPE=NA, RMSE=NA))
      yhat_vec <- df2[[yhat_col_name]]
      mape <- mean(abs((df2$actual - yhat_vec)/df2$actual))*100
      rmse <- sqrt(mean((df2$actual - yhat_vec)^2))
      list(MAPE=mape, RMSE=rmse)
    }
    
    m1_2025 <- calc_metrics_2025(cmp_base_2025, "yhat_base")
    m2_2025 <- calc_metrics_2025(cmp_tuned_2025, "yhat_tuned")
    
    #In kết quả Validation ra Console
    cat("\n--- Validation (on 2024 data) ---\n")
    cat("Best CPS: ", best_cps, "\n")
    cat("Best SPS: ", best_sps, "\n")
    cat("Tuned MAPE (Validation): ", round(best_mape, 3), "%\n")
    cat("Tuned RMSE (Validation): ", round(best_rmse, 2), "\n")
    cat("Base MAPE (Validation) : ", round(base_mape_val, 3), "%\n") 
    cat("Base RMSE (Validation) : ", round(base_rmse_val, 2), "\n") 
    cat("---------------------------------\n")
    
    #In kết quả Test 2025 ra Console
    cat("\n===== KẾT QUẢ TRÊN TEST SET (2025) CHO", target_name, "=====\n")
    cat("Baseline Prophet : MAPE =", round(m1_2025$MAPE,2), "% | RMSE =", round(m1_2025$RMSE,2), "\n")
    cat("Tuned Prophet    : MAPE =", round(m2_2025$MAPE,2), "% | RMSE =", round(m2_2025$RMSE,2), "\n")
    
    
    output$status <- renderText(paste("Done.")) 
    
    # Gửi metrics 2025 vào UI
    metrics_summary_text <- paste(
      "--- Tuned Model (Test 2025) ---",
      paste("Best CPS:", best_cps), 
      paste("Best SPS:", best_sps),
      paste("Tuned MAPE:", round(m2_2025$MAPE, 2), "%"), 
      paste("Tuned RMSE:", round(m2_2025$RMSE, 2)),      
      "\n--- Baseline Model (Test 2025) ---",
      paste("Base MAPE:", round(m1_2025$MAPE, 2), "%"), 
      paste("Base RMSE:", round(m1_2025$RMSE, 2)),      
      sep = "\n"
    )
    output$best_metrics_ui <- renderText({ metrics_summary_text })
    
    
    #RENDER PLOT 1
    output$plot_forecast_only <- renderPlot({
      df_plot <- rv$cmp_all %>% 
        filter(ds > last_train_date)
      if (is.null(df_plot) || nrow(df_plot) == 0) {
        plot.new(); text(0.5, 0.5, "No forecast data to plot")
        return(NULL)
      }
      ggplot(df_plot, aes(x = ds)) +
        geom_ribbon(aes(ymin = yhat_lower_tuned, ymax = yhat_upper_tuned), fill = "blue", alpha = 0.4) + 
        geom_line(aes(y = yhat_tuned, color = "Forecast (tuned)"), size = 1.2) +
        scale_color_manual(values = c("Forecast (tuned)" = "blue")) +
        scale_y_continuous(labels = scales::comma) +
        labs(title = paste("Forecast -", target_name),
             x = "Month", y = "Value", color = "") +
        theme_minimal(base_size = 13) +
        theme(legend.position = "top")
    })
    
    #RENDER PLOT 2
    output$plot_forecast_actual <- renderPlot({
      df_plot_actual <- rv$cmp_all %>% 
        filter(ds > last_train_date)
      if (is.null(df_plot_actual) || nrow(df_plot_actual) == 0) {
        plot.new(); text(0.5, 0.5, "No data to plot")
        return(NULL)
      }
      ggplot(df_plot_actual, aes(x = ds)) +
        geom_ribbon(aes(ymin = yhat_lower_tuned, ymax = yhat_upper_tuned), fill = "blue", alpha = 0.4) +
        geom_line(aes(y = yhat_tuned, color = "Forecast (tuned)"), size = 1.2) + 
        geom_line(aes(y = actual, color = "Actual 2025"), linetype = "dashed", size = 1.0, na.rm = TRUE) + 
        geom_point(aes(y = actual, color = "Actual 2025"), size = 2.5, na.rm = TRUE) +
        scale_color_manual(values = c(
          "Forecast (tuned)" = "blue", 
          "Actual 2025" = "red"
        )) +
        scale_y_continuous(labels = scales::comma) +
        labs(title = paste("Tuned vs Actual (2025) -", target_name), 
             x = "Month", y = "Value", color = "") +
        theme_minimal(base_size = 13) +
        theme(legend.position = "top")
    })
    
    #RENDER PLOT 3
    output$plot_baseline_actual <- renderPlot({
      df_plot_all_compare <- rv$cmp_all %>% 
        filter(ds > last_train_date)
      if (is.null(df_plot_all_compare) || nrow(df_plot_all_compare) == 0) {
        plot.new(); text(0.5, 0.5, "No data to plot")
        return(NULL)
      }
      ggplot(df_plot_all_compare, aes(x = ds)) +
        geom_line(aes(y = yhat_base, color = "Baseline Forecast"), size = 1.2, linetype = "longdash") + 
        geom_line(aes(y = yhat_tuned, color = "Forecast (tuned)"), size = 1.2, linetype = "solid") + 
        geom_line(aes(y = actual, color = "Actual 2025"), linetype = "dashed", size = 1.0, na.rm = TRUE) +
        geom_point(aes(y = actual, color = "Actual 2025"), size = 2.5, na.rm = TRUE) +
        scale_color_manual(values = c(
          "Baseline Forecast" = "darkgreen", 
          "Forecast (tuned)" = "blue",
          "Actual 2025" = "red"
        )) +
        scale_y_continuous(labels = scales::comma) +
        labs(title = paste("Baseline, Actual & Tuned (2025) -", target_name), 
             x = "Month", y = "Value", color = "") +
        theme_minimal(base_size = 13) +
        theme(legend.position = "top")
    })
    
  })
} # end server


#Run app
shinyApp(ui = ui, server = server)






