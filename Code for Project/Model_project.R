#Dự đoán 1 data
library(prophet)
library(ggplot2)
library(readr)
library(dplyr)
library(tidyr)
library(scales)

#️ĐỌC DỮ LIỆU
data_raw <- read_csv("D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged_summary.csv")
#LỌC DỮ LIỆU THEO YÊU CẦU
data_eu <- data_raw %>%
  filter(
    Names == "Ukraine",
    Group == "Summary"       # chỉ lấy dòng tổng hợp
  )

#CHUYỂN WIDE → LONG (gom tháng)
data_eu_long <- data_eu %>%
  pivot_longer(
    cols = ends_with("_Value"),
    names_to = "Month",
    values_to = "y"
  ) %>%
  mutate(
    Month = sub("_Value", "", Month),
    month_num = match(Month, month.name),
    ds = as.Date(paste0(Year, "-", month_num, "-01"), format = "%Y-%m-%d")
  ) %>%
  group_by(ds) %>%
  summarise(y = sum(y, na.rm = TRUE)) %>%
  arrange(ds) %>%
  filter(!is.na(ds) & !is.na(y))

#TẠO MÔ HÌNH PROPHET
model_prophet <- prophet(
  growth = "linear",
  yearly.seasonality = TRUE,
  weekly.seasonality = FALSE,
  daily.seasonality = FALSE,
  changepoint.prior.scale = 0.5,
  interval.width = 0.95
)

model_prophet <- fit.prophet(model_prophet, data_eu_long)

#DỰ BÁO 12 THÁNG TIẾP THEO
future <- make_future_dataframe(model_prophet, periods = 12, freq = "month")
forecast <- predict(model_prophet, future)

#VẼ BIỂU ĐỒ DỰ BÁO
name <- unique(data_eu$Names)

plot(model_prophet, forecast) +
  ggtitle(paste("Prophet Forecast –", name, "Import (Next 12 Months)")) +
  xlab("Năm") + 
  ylab("Giá trị xuất khẩu (VND)") +
  theme_minimal(base_size = 13) +
  scale_y_continuous(labels = comma)

#HIỂN THỊ THÀNH PHẦN (xu hướng + mùa vụ)

prophet_plot_components(model_prophet, forecast)

#XEM DỰ BÁO CỤ THỂ
forecast %>%
  select(ds, yhat, yhat_lower, yhat_upper) %>%
  tail(12)



############################################################


#Dự đoán 2 data
library(tidyverse)
library(prophet)
library(scales)
library(lubridate)

#ĐỌC DỮ LIỆU GỐC
data_raw <- read_csv("D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged_summary.csv")
data_2025 <- read_csv("D:\\Download\\Data for subject\\DSR_cleaned\\Im05-2025-6_clean.csv")

#CHỌN TÊN KHU VỰC 
target_name <- "Ukraine"  

#DỮ LIỆU THỰC TẾ NĂM 2025
actual_df <- data_2025 %>%
  filter(Names == target_name, is.na(Group)) %>%
  pivot_longer(
    cols = ends_with("_Value"),
    names_to = "Month",
    values_to = "actual"
  ) %>%
  mutate(
    Month = str_replace(Month, "_Value", ""),
    Month = str_to_title(Month),
    month_num = match(Month, month.name),
    ds = as.Date(paste(2025, month_num, "01", sep = "-"), format = "%Y-%m-%d")
  ) %>%
  select(ds, actual) %>%
  arrange(ds)

#DỮ LIỆU TRAIN PROPHET (2022–2024)
train_df <- data_raw %>%
  filter(Names == target_name, Group == "Summary", Year >= 2022 & Year <= 2024) %>%
  pivot_longer(
    cols = ends_with("_Value"),
    names_to = "Month",
    values_to = "y"
  ) %>%
  mutate(
    Month = str_replace(Month, "_Value", ""),
    Month = str_to_title(Month),
    month_num = match(Month, month.name),
    ds = as.Date(paste0(Year, "-", month_num, "-01"), format = "%Y-%m-%d")
  ) %>%
  group_by(ds) %>%
  summarise(y = sum(y, na.rm = TRUE)) %>%
  arrange(ds) %>%
  filter(!is.na(ds) & !is.na(y))

#FIT PROPHET MODEL
m <- prophet(
  growth = "linear",
  yearly.seasonality = TRUE,
  weekly.seasonality = FALSE,
  daily.seasonality = FALSE,
  changepoint.prior.scale = 0.5,
  interval.width = 0.95
)

m <- fit.prophet(m, train_df)

#DỰ BÁO 12 THÁNG TIẾP THEO
future <- make_future_dataframe(m, periods = 12, freq = "month")
forecast <- predict(m, future)

#GHÉP DỮ LIỆU DỰ BÁO & THỰC TẾ
compare_df <- forecast %>%
  select(ds, yhat, yhat_lower, yhat_upper) %>%
  left_join(actual_df, by = "ds") %>%
  filter(year(ds) == 2025)

#BIỂU ĐỒ SO SÁNH DỰ BÁO – THỰC TẾ
ggplot(compare_df, aes(x = ds)) +
  geom_ribbon(aes(ymin = yhat_lower, ymax = yhat_upper),
              fill = "lightblue", alpha = 0.4) +
  geom_line(aes(y = yhat, color = "Dự báo Prophet"), size = 1.2) +
  geom_point(aes(y = actual, color = "Thực tế"), size = 2.5) +
  geom_line(aes(y = actual, color = "Thực tế"), linetype = "dashed", size = 1.1) +
  geom_text(aes(y = actual, label = comma(round(actual, 0))),
            vjust = -0.8, size = 3) +
  scale_color_manual(values = c("Dự báo Prophet" = "blue", "Thực tế" = "red")) +
  labs(
    title = paste("So sánh Dự báo Prophet và Dữ liệu Thực tế –", target_name, "(2025)"),
    x = "Tháng",
    y = "Giá trị xuất khẩu (VND)",
    color = ""
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "top")

#ĐÁNH GIÁ MỨC ĐỘ CHÍNH XÁC

compare_df <- compare_df %>% drop_na(actual)

mape <- mean(abs((compare_df$actual - compare_df$yhat) / compare_df$actual)) * 100
rmse <- sqrt(mean((compare_df$actual - compare_df$yhat)^2))

cat("Kết quả cho khu vực:", target_name, "\n")
cat("MAPE:", round(mape, 2), "%\n")
cat("RMSE:", round(rmse, 2), "\n")








################################################################################
################################################################################
# ====== Thư viện & cài đặt ======
if (!requireNamespace("prophet", quietly = TRUE)) install.packages("prophet")
if (!requireNamespace("tidyverse", quietly = TRUE)) install.packages("tidyverse")
if (!requireNamespace("lubridate", quietly = TRUE)) install.packages("lubridate")
if (!requireNamespace("zoo", quietly = TRUE)) install.packages("zoo")

library(tidyverse)
library(prophet)
library(lubridate)
library(scales)
library(zoo)

################################################################################
# ====== Thông số người dùng ======
data_raw_path  <- "D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged_summary.csv"
data_2025_path <- "D:\\Download\\Data for subject\\DSR_cleaned\\Im05-2025-6_clean.csv"
target_name    <- "Ukraine"   # chỉ quốc gia này dùng rolling CV
auto_log_check <- TRUE

################################################################################
# ====== 1) Đọc dữ liệu ======
data_raw_all <- read_csv(data_raw_path, show_col_types = FALSE)
data_2025     <- read_csv(data_2025_path, show_col_types = FALSE)

################################################################################
# ====== 2) Chuẩn bị actual 2025 ======
actual_df <- data_2025 %>%
  filter(Names == target_name, is.na(Group)) %>%
  pivot_longer(cols = ends_with("_Value"), names_to = "Month", values_to = "actual") %>%
  mutate(
    Month = str_replace(Month, "_Value", ""),
    Month = str_to_title(Month),
    month_num = match(Month, month.name),
    ds = as.Date(paste(2025, month_num, "01", sep = "-")),
    actual = as.numeric(actual)
  ) %>%
  select(ds, actual) %>%
  arrange(ds)

################################################################################
# ====== 3) Chuẩn bị train 2022-2024 ======
train_df <- data_raw_all %>%
  filter(Names == target_name, Group == "Summary", Year >= 2022 & Year <= 2024) %>%
  pivot_longer(cols = ends_with("_Value"), names_to = "Month", values_to = "y") %>%
  mutate(
    Month = str_replace(Month, "_Value", ""),
    Month = str_to_title(Month),
    month_num = match(Month, month.name),
    ds = as.Date(paste0(Year, "-", month_num, "-01")),
    y = as.numeric(y)
  ) %>%
  group_by(ds) %>%
  summarise(y = sum(y, na.rm = TRUE), .groups = "drop") %>%
  arrange(ds) %>%
  filter(!is.na(ds))

if (nrow(train_df) == 0) stop("No training rows found for the selected target_name.")
cat("Train rows:", nrow(train_df), "from", min(train_df$ds), "to", max(train_df$ds), "\n")

################################################################################
# ====== 4) Xử lý missing ======
if (any(is.na(train_df$y))) {
  train_df$y <- na.approx(train_df$y, na.rm = FALSE)
  train_df$y <- na.locf(train_df$y, na.rm = FALSE)
  train_df$y <- na.locf(train_df$y, fromLast = TRUE)
}
if (any(is.na(train_df$y))) train_df$y[is.na(train_df$y)] <- median(train_df$y, na.rm = TRUE)

################################################################################
# ====== 5) Auto log-transform ======
need_log <- FALSE
if (auto_log_check) {
  n <- nrow(train_df)
  if (n >= 6) {
    half <- floor(n / 2)
    v1 <- var(train_df$y[1:half], na.rm = TRUE)
    v2 <- var(train_df$y[(half + 1):n], na.rm = TRUE)
    mean1 <- mean(train_df$y[1:half], na.rm = TRUE)
    mean2 <- mean(train_df$y[(half + 1):n], na.rm = TRUE)
    if (!is.na(v1) && !is.na(v2) && mean2 > mean1 && v2 > v1 * 1.5) need_log <- TRUE
  }
}
cat("Auto-log decision:", need_log, "\n")

if (need_log) {
  min_pos <- min(train_df$y[train_df$y > 0], na.rm = TRUE)
  if (!is.finite(min_pos)) min_pos <- 1
  train_df$y[train_df$y <= 0] <- min_pos * 0.01
}

################################################################################
# ====== 6) Thêm biến tháng ======
make_month_regressors <- function(df) {
  df2 <- df %>% mutate(m = month(ds))
  for (m in 1:12) df2[[paste0("m_", m)]] <- as.integer(df2$m == m)
  df2 %>% select(-m)
}
train_reg <- make_month_regressors(train_df)
regressor_names <- paste0("m_", 1:12)
prophet_train <- train_reg %>% select(ds, y, all_of(regressor_names))
if (need_log) prophet_train <- prophet_train %>% mutate(y = log1p(y))

################################################################################
# ====== 7) Cấu hình Cross-Validation RIÊNG CHO UKRAINE ======
use_rolling_cv <- (target_name == "Ukraine")

cps_grid <- c(0.001, 0.005, 0.01, 0.05, 0.1)
sps_grid <- c(0.1, 0.5, 1, 5, 10)

safe_n_changepoints <- function(n_rows) min(max(floor(n_rows * 0.8), 1), 25)
n_obs <- nrow(prophet_train)
best_cps <- 0.05
best_sps <- 1
best_mape <- Inf

if (use_rolling_cv) {
  cat("⚙️ Using rolling cross-validation for", target_name, "...\n")
  
  initial_days <- max(365, floor(n_obs * 0.5 * 30))
  period_days  <- max(90, floor(n_obs * 0.1 * 30))
  horizon_days <- min(365, max(90, floor(n_obs * 0.25 * 30)))
  
  for (cps in cps_grid) {
    for (sps in sps_grid) {
      cat("  Testing cps =", cps, "| sps =", sps, "...\n")
      mtmp <- prophet(
        growth = "linear",
        yearly.seasonality = TRUE,
        weekly.seasonality = FALSE,
        daily.seasonality = FALSE,
        seasonality.mode = "additive",
        changepoint.prior.scale = cps,
        seasonality.prior.scale = sps,
        changepoint.range = 0.8,
        n.changepoints = safe_n_changepoints(n_obs)
      )
      for (r in regressor_names) mtmp <- add_regressor(mtmp, r, standardize = TRUE)
      
      tryCatch({
        mtmp <- fit.prophet(mtmp, prophet_train)
        df_cv <- cross_validation(mtmp,
                                  initial = initial_days,
                                  period  = period_days,
                                  horizon = horizon_days,
                                  units = 'days')
        perf <- performance_metrics(df_cv)
        mape_mean <- mean(perf$mape, na.rm = TRUE) * 100
        cat("     MAPE =", round(mape_mean, 2), "\n")
        
        if (mape_mean < best_mape) {
          best_mape <- mape_mean
          best_cps <- cps
          best_sps <- sps
        }
      }, error = function(e) cat("Error:", conditionMessage(e), "\n"))
    }
  }
  cat("Best for", target_name, "cps =", best_cps, "| sps =", best_sps, "| MAPE =", round(best_mape, 3), "\n")
}

################################################################################
# ====== 8) Fit model cuối ======
m_final <- prophet(
  growth = "linear",
  yearly.seasonality = TRUE,
  weekly.seasonality = FALSE,
  daily.seasonality = FALSE,
  seasonality.mode = "additive",
  changepoint.range = 0.8,
  changepoint.prior.scale = best_cps,
  seasonality.prior.scale = best_sps,
  n.changepoints = safe_n_changepoints(n_obs)
)
for (r in regressor_names) m_final <- add_regressor(m_final, r, standardize = TRUE)
m_final <- fit.prophet(m_final, prophet_train)

################################################################################
# ====== 9) Dự báo 2025 & Back-transform ======
future_df <- make_future_dataframe(m_final, periods = 12, freq = "month") %>%
  mutate(month = month(ds))
for (m in 1:12) future_df[[paste0("m_", m)]] <- as.integer(month(future_df$ds) == m)

pred <- predict(m_final, future_df) %>%
  select(ds, yhat, yhat_lower, yhat_upper)
if (need_log) {
  pred <- pred %>%
    mutate(yhat = pmax(expm1(yhat), 0),
           yhat_lower = pmax(expm1(yhat_lower), 0),
           yhat_upper = pmax(expm1(yhat_upper), 0))
}

################################################################################
# ====== 10) Đánh giá với actual ======
cmp <- pred %>% left_join(actual_df, by = "ds") %>% filter(year(ds) == 2025) %>% drop_na(actual)
if (nrow(cmp) > 0) {
  mape <- mean(abs((cmp$actual - cmp$yhat) / cmp$actual)) * 100
  rmse <- sqrt(mean((cmp$actual - cmp$yhat)^2))
  cat("\n===== FINAL RESULT for", target_name, "=====\n")
  cat("MAPE:", round(mape, 3), "% | RMSE:", round(rmse, 2), "\n")
}

################################################################################
# ====== 11) Biểu đồ ======
library(ggplot2)
ggplot(cmp, aes(x = ds)) +
  geom_ribbon(aes(ymin = yhat_lower, ymax = yhat_upper), fill = "lightblue", alpha = 0.3) +
  geom_line(aes(y = yhat, color = "Forecast"), size = 1.2) +
  geom_point(aes(y = actual, color = "Actual"), size = 2.5) +
  geom_line(aes(y = actual, color = "Actual"), linetype = "dashed", size = 1.1) +
  scale_color_manual(values = c("Forecast" = "blue", "Actual" = "red")) +
  scale_y_continuous(labels = comma) +
  labs(title = paste("Prophet forecast vs Actual -", target_name, "(2025)"),
       x = "Month", y = "Value", color = "") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "top")
