#Cho file Export
library(readxl)
library(dplyr)
library(tidyr)
library(stringr)

path <- "D:\\Download\\Im05-2025-6.xls"

# 1) Đọc 2 dòng header (dòng 4 và 5)
header <- read_excel(path, skip = 3, n_max = 2, col_names = FALSE)

# Debug: in header ra để kiểm tra
cat("== Header (2 rows) ==\n")
print(header)

# 2) Tìm cột bắt đầu chứa tên tháng (tự động)
months_list <- c("January","February","March","April","May","June","July","August","September","October","November","December")
pattern <- paste(months_list, collapse = "|")

# tìm cột đầu tiên mà row1 hoặc row2 chứa 1 trong tên tháng
cols_with_month <- which(sapply(1:ncol(header), function(i) {
  any(grepl(pattern, as.character(header[1,i]), ignore.case = TRUE),
      grepl(pattern, as.character(header[2,i]), ignore.case = TRUE))
}))
start_col <- if(length(cols_with_month) > 0) cols_with_month[1] else 3  # fallback = 3

cat("Start column detected (should be where January begins):", start_col, "\n")

# 3) Lấy phần header từ start_col trở đi
months_raw <- as.character(unlist(header[1, start_col:ncol(header)]))
sub_raw    <- as.character(unlist(header[2, start_col:ncol(header)]))

# 4) Điền NA do merged cells (lấy giá trị trước đó)
months_filled <- fill(data.frame(month = months_raw, stringsAsFactors = FALSE), month)$month

# 5) Làm sạch subheader: bỏ phần xuống dòng và ngoặc, trim
sub_clean <- str_replace_all(sub_raw, "\\n.*", "")   # bỏ "\n(...)"
sub_clean <- str_trim(sub_clean)
sub_clean[is.na(sub_clean)] <- ""                    # thay NA bằng rỗng

# 6) Ghép tên cột cho phần tháng: nếu sub_clean rỗng thì chỉ lấy month
month_cols_all <- ifelse(sub_clean == "", months_filled, paste0(months_filled, "_", sub_clean))

# debug: hiển thị 1 vài month_cols
cat("First 20 month_cols (from detected start_col):\n")
print(head(month_cols_all, 20))

# 7) Tạo tên cột hoàn chỉnh: 2 cột đầu đặt tay Names, Group
col_names_full <- c("Names", "Group", month_cols_all)

# 8) Đọc dữ liệu thực tế từ dòng 6 trở đi
data <- read_excel(path, skip = 5, col_names = FALSE)

# 9) Đồng bộ số cột: nếu month_cols nhiều hơn dữ liệu -> cắt; nếu ít -> thêm NA names
needed <- length(col_names_full)
current <- ncol(data)
cat("Data columns read:", current, "    Column names available:", needed, "\n")

if (current < needed) {
  # nếu dữ liệu ít cột hơn tên => chỉ dùng tương ứng
  col_names_to_assign <- col_names_full[1:current]
} else if (current > needed) {
  # nếu dữ liệu nhiều cột hơn tên => mở rộng tên bằng suffix số để không mất cột
  extra <- current - needed
  extra_names <- paste0("ExtraCol", seq_len(extra))
  col_names_to_assign <- c(col_names_full, extra_names)
} else {
  col_names_to_assign <- col_names_full
}

# 10) Gán tên cột
colnames(data) <- col_names_to_assign

# 11) Làm sạch tên cột (loại \n, (), khoảng trắng -> _)
colnames(data) <- str_replace_all(colnames(data), "\\n.*", "")
colnames(data) <- str_replace_all(colnames(data), "\\s+", "_")
colnames(data) <- str_replace_all(colnames(data), "[\\(\\)]", "")

cat("Final column names (first 15):\n")
print(colnames(data)[1:min(15, ncol(data))])

# 12) Kiểm tra xem "January" có xuất hiện trong tên cột không
cat("Columns containing 'January':\n")
print(grep("January", colnames(data), value = TRUE))

data <- data %>%
  fill(Names, .direction = "down")
data <- data %>%
  filter(!grepl("^Of which", Group))

# Lưu xuống CSV
write.csv(data, "D:/Download/Data for subject/DSR_cleaned/Im05-2025-6_clean.csv", row.names = FALSE)

# 13) Hiển thị vài dòng đầu
print(head(data, 8))

################################################################################
#Cho file Import
library(readxl)
library(dplyr)
library(tidyr)
library(stringr)

# Thiết lập đường dẫn file (sử dụng đường dẫn bạn cung cấp)
path <- "D:\\Download\\Im05-2025-6.xls"

# 1) Đọc 2 dòng header (dòng 4 và 5)
header <- read_excel(path, skip = 3, n_max = 2, col_names = FALSE)

# Debug: in header ra để kiểm tra
cat("== Header (2 rows) ==\n")
print(header)

# 2) Tìm cột bắt đầu chứa tên tháng (tự động)
months_list <- c("January","February","March","April","May","June","July","August","September","October","November","December")
pattern <- paste(months_list, collapse = "|")

# tìm cột đầu tiên mà row1 hoặc row2 chứa 1 trong tên tháng
cols_with_month <- which(sapply(1:ncol(header), function(i) {
  any(grepl(pattern, as.character(header[1,i]), ignore.case = TRUE),
      grepl(pattern, as.character(header[2,i]), ignore.case = TRUE))
}))
start_col <- if(length(cols_with_month) > 0) cols_with_month[1] else 4 # fallback = 4 (vì có 3 cột metadata: Name, Group, Unit)

cat("Start column detected (should be where January begins):", start_col, "\n")

# 3) Lấy phần header từ start_col trở đi
months_raw <- as.character(unlist(header[1, start_col:ncol(header)]))
sub_raw    <- as.character(unlist(header[2, start_col:ncol(header)]))

# 4) Điền NA do merged cells (lấy giá trị trước đó)
months_filled <- fill(data.frame(month = months_raw, stringsAsFactors = FALSE), month)$month

# 5) Làm sạch subheader: bỏ phần xuống dòng và ngoặc, trim
sub_clean <- str_replace_all(sub_raw, "\\n.*", "")  # bỏ "\n(...)"
sub_clean <- str_trim(sub_clean)
sub_clean[is.na(sub_clean)] <- ""                  # thay NA bằng rỗng

# 6) Ghép tên cột cho phần tháng: nếu sub_clean rỗng thì chỉ lấy month
month_cols_all <- ifelse(sub_clean == "", months_filled, paste0(months_filled, "_", sub_clean))

# debug: hiển thị 1 vài month_cols
cat("First 20 month_cols (from detected start_col):\n")
print(head(month_cols_all, 20))

# 7) Tạo tên cột hoàn chỉnh: 3 cột đầu đặt tay Names, Group, Unit (theo thứ tự dữ liệu)
# Names là cột 1 (thường là rỗng trong header), Group là cột 2, Unit là cột 3.
col_names_full <- c("Names", "Group", "Unit", month_cols_all)

# 8) Đọc dữ liệu thực tế từ dòng 6 trở đi
data <- read_excel(path, skip = 5, col_names = FALSE)

# 9) Đồng bộ số cột: nếu month_cols nhiều hơn dữ liệu -> cắt; nếu ít -> thêm NA names
needed <- length(col_names_full)
current <- ncol(data)
cat("Data columns read:", current, "    Column names available:", needed, "\n")

if (current < needed) {
  # nếu dữ liệu ít cột hơn tên => chỉ dùng tương ứng
  col_names_to_assign <- col_names_full[1:current]
} else if (current > needed) {
  # nếu dữ liệu nhiều cột hơn tên => mở rộng tên bằng suffix số để không mất cột
  extra <- current - needed
  extra_names <- paste0("ExtraCol", seq_len(extra))
  col_names_to_assign <- c(col_names_full, extra_names)
} else {
  col_names_to_assign <- col_names_full
}

# 10) Gán tên cột
colnames(data) <- col_names_to_assign

# 11) Làm sạch tên cột (loại \n, (), khoảng trắng -> _)
colnames(data) <- str_replace_all(colnames(data), "\\n.*", "")
colnames(data) <- str_replace_all(colnames(data), "\\s+", "_")
colnames(data) <- str_replace_all(colnames(data), "[\\(\\)]", "")

# 11.5) Lọc bỏ cột Unit theo yêu cầu
data <- data %>%
  select(-Unit)

# 12) Kiểm tra xem "January" có xuất hiện trong tên cột không
cat("Columns containing 'January':\n")
print(grep("January", colnames(data), value = TRUE))

# Tiếp tục các bước làm sạch dữ liệu
data <- data %>%
  fill(Names, .direction = "down")
data <- data %>%
  filter(!grepl("^Of which", Group))

# Lưu xuống CSV
write.csv(data, "D:/Download/Data for subject/DSR_cleaned/Im05-2025-6_clean.csv", row.names = FALSE)

# 13) Hiển thị vài dòng đầu
print(head(data, 8))


################################################################################

library(readxl)
library(dplyr)
library(purrr)

library(dplyr)

# ===== BƯỚC 1: Liệt kê các file cần gộp =====
files <- c("D:/Download/Data for subject/DSR_cleaned/Im05-2022-11_clean.csv",
           "D:/Download/Data for subject/DSR_cleaned/Im05-2023-8_clean.csv",
           "D:/Download/Data for subject/DSR_cleaned/Im05-2024-6_clean.csv")

# ===== BƯỚC 2: Đọc và gộp dữ liệu =====
all_data <- files %>%
  lapply(read.csv) %>%
  bind_rows(.id = "FileID")

# ===== BƯỚC 3: Thêm cột Year từ tên file =====
all_data <- all_data %>%
  mutate(Year = gsub(".*Im05-(\\d{4})-.*", "\\1", files[as.integer(FileID)]))

# ===== BƯỚC 4: Xuất dữ liệu đã gộp =====
write.csv(all_data,
          "D:/Download/Data for subject/DSR_cleaned/Im05_2022_2024_merged.csv",
          row.names = FALSE)

# Kiểm tra kết quả
head(all_data)

library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)

# Đọc dữ liệu
data_export <- read_csv("D:\\Download\\Data for subject\\DSR_cleaned\\Ex04_2022_2024_merged.csv")

# Lọc năm 2024 và chỉ lấy tổng (Group = NA)
export_2024 <- data_export %>%
  filter(Year == 2023, is.na(Group)) %>%
  mutate(X12_months_Value = as.numeric(gsub(",", "", X12_months_Value)))

# Biểu đồ 1: Thị trường xuất khẩu lớn (> 10 triệu USD)
big_export <- export_2024 %>%
  filter(X12_months_Value > 10000000) %>%
  arrange(desc(X12_months_Value))

p1 <- ggplot(big_export, aes(x = reorder(Names, X12_months_Value),
                             y = X12_months_Value,
                             fill = Names)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_y_continuous(labels = comma_format()) +
  labs(title = "Thị trường xuất khẩu lớn ( > 10 triệu USD, năm 2024)",
       x = "Quốc gia",
       y = "Giá trị xuất khẩu (USD)") +
  theme_minimal()

# Biểu đồ 2: Thị trường xuất khẩu nhỏ (≤ 10 triệu USD)
small_export <- export_2024 %>%
  filter(X12_months_Value <= 10000000) %>%
  arrange(desc(X12_months_Value))

p2 <- ggplot(small_export, aes(x = reorder(Names, X12_months_Value),
                               y = X12_months_Value,
                               fill = Names)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_y_continuous(labels = comma_format()) +
  labs(title = "Thị trường xuất khẩu nhỏ ( ≤ 10 triệu USD, năm 2024)",
       x = "Quốc gia",
       y = "Giá trị xuất khẩu (USD)") +
  theme_minimal()

# Hiển thị 2 biểu đồ
p1
p2
##################################
# Lọc năm 2024 (có thể thay bằng 2022 hoặc 2023 nếu muốn)
data_import <- read_csv("D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged.csv")

# Lọc năm 2024 và chỉ lấy tổng (Group = NA)
import_2024 <- data_import %>%
  filter(Year == 2023, is.na(Group)) %>%
  mutate(X12_months_Value = as.numeric(gsub(",", "", X12_months_Value)))

# Biểu đồ 1: Thị trường lớn (> 10 triệu USD)
big_markets <- import_2024 %>%
  filter(X12_months_Value > 10000000) %>%
  arrange(desc(X12_months_Value))

p1 <- ggplot(big_markets, aes(x = reorder(Names, X12_months_Value),
                              y = X12_months_Value,
                              fill = Names)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_y_continuous(labels = comma_format()) +
  labs(title = "Thị trường nhập khẩu lớn ( > 10 triệu USD, năm 2024)",
       x = "Quốc gia",
       y = "Giá trị nhập khẩu (USD)") +
  theme_minimal()

# Biểu đồ 2: Thị trường nhỏ (≤ 10 triệu USD)
small_markets <- import_2024 %>%
  filter(X12_months_Value <= 10000000) %>%
  arrange(desc(X12_months_Value))

p2 <- ggplot(small_markets, aes(x = reorder(Names, X12_months_Value),
                                y = X12_months_Value,
                                fill = Names)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_y_continuous(labels = comma_format()) +
  labs(title = "Thị trường nhập khẩu nhỏ ( ≤ 10 triệu USD, năm 2024)",
       x = "Quốc gia",
       y = "Giá trị nhập khẩu (USD)") +
  theme_minimal()

# Hiển thị cả 2 biểu đồ
p1
p2

# Tổng xuất khẩu theo năm
export_yearly <- data_import %>%
  filter(is.na(Group)) %>%   # chỉ lấy tổng
  mutate(X12_months_Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Year) %>%
  summarise(total_export = sum(X12_months_Value, na.rm = TRUE))

# Vẽ line chart
ggplot(export_yearly, aes(x = Year, y = total_export)) +
  geom_line(color = "pink", size = 1.8) +
  geom_point(color = "red", size = 5) +
  scale_y_continuous(labels = comma_format()) +
  scale_x_continuous(breaks = 2022:2024) +
  geom_text(aes(label = scales::comma(total_export)),
            vjust = -1, size = 5, color = "black") +
  labs(title = "Xu hướng tổng giá trị nhập khẩu (2022–2024)",
       x = "Năm",
       y = "Giá trị nhập khẩu (USD)") +
  theme_minimal()
###################################

# Tổng export theo năm
export_yearly <- data_export %>%
  filter(is.na(Group)) %>%
  mutate(X12_months_Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Year) %>%
  summarise(total_export = sum(X12_months_Value, na.rm = TRUE))

# Tổng import theo năm
import_yearly <- data_import %>%
  filter(is.na(Group)) %>%
  mutate(X12_months_Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Year) %>%
  summarise(total_import = sum(X12_months_Value, na.rm = TRUE))

# Gộp 2 bảng
trade_yearly <- merge(export_yearly, import_yearly, by = "Year")

# Đưa về long format để dễ vẽ ggplot
library(tidyr)
trade_long <- trade_yearly %>%
  pivot_longer(cols = c(total_export, total_import),
               names_to = "Type", values_to = "Value")

# Vẽ line chart
ggplot(trade_long, aes(x = Year, y = Value, color = Type, group = Type)) +
  geom_line(size = 1.2) +
  geom_point(size = 3) +
  geom_text(aes(label = scales::comma(Value)), vjust = -1, size = 4, show.legend = FALSE) +
  scale_y_continuous(labels = comma) +
  labs(title = "So sánh tổng xuất khẩu và nhập khẩu theo năm",
       x = "Năm", y = "Giá trị (USD)", color = "Loại") +
  theme_minimal()

####################################
# Chuẩn hóa EXPORT
export_clean <- data_export %>%
  filter(is.na(Group)) %>%
  mutate(X12_months_Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Year, Names) %>%
  summarise(total_export = sum(X12_months_Value, na.rm = TRUE), .groups = "drop")

# Chuẩn hóa IMPORT
import_clean <- data_import %>%
  filter(is.na(Group)) %>%
  mutate(X12_months_Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Year, Names) %>%
  summarise(total_import = sum(X12_months_Value, na.rm = TRUE), .groups = "drop")

# Kết hợp và tính Cán cân thương mại
trade_balance <- export_clean %>%
  full_join(import_clean, by = c("Year", "Names")) %>%
  mutate(trade_balance = total_export - total_import)

# Vẽ biểu đồ cán cân thương mại (top 10 quốc gia mỗi năm)
top_balance <- trade_balance %>%
  group_by(Year) %>%
  slice_max(order_by = abs(trade_balance), n = 10)  # lấy theo độ lớn tuyệt đối

ggplot(top_balance, aes(x = reorder(Names, trade_balance), 
                        y = trade_balance, fill = trade_balance > 0)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  scale_y_continuous(labels = comma) +
  facet_wrap(~Year, scales = "free_y") +
  labs(title = "Cán cân thương mại theo quốc gia (Top 10, 2022–2024)",
       x = "Quốc gia",
       y = "Cán cân thương mại (Xuất - Nhập, USD)") +
  scale_fill_manual(values = c("red", "green")) +   # lỗ = đỏ, lãi = xanh
  theme_minimal()
#############################################

# Chuẩn bị dữ liệu export
export_heatmap <- data_export %>%
  filter(is.na(Group)) %>%   # lấy tổng theo từng quốc gia
  mutate(Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Names, Year) %>%
  summarise(total_export = sum(Value, na.rm = TRUE), .groups = "drop")

# Vẽ heatmap
ggplot(export_heatmap, aes(x = factor(Year), y = reorder(Names, total_export), fill = total_export)) +
  geom_tile(color = "white") +
  scale_fill_gradient(low = "lightblue", high = "darkblue",
                      labels = comma, name = "Giá trị xuất khẩu (USD)") +
  labs(title = "Thị trường xuất khẩu tiềm năng (2022–2024)",
       x = "Năm",
       y = "Quốc gia") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
#####################################################

# ====== DỮ LIỆU EXPORT ======
import_group <- data_export %>%
  filter(!is.na(Group)) %>%   # bỏ NA (dòng tổng quốc gia)
  filter(!grepl("TOTAL", Group, ignore.case = TRUE)) %>%  # bỏ các dòng ghi tổng mặt hàng
  mutate(Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Group, Year) %>%
  summarise(total_import = sum(Value, na.rm = TRUE), .groups = "drop")

# Vẽ stacked area chart cho EXPORT
ggplot(import_group, aes(x = reorder(Group, total_import), 
                         y = total_import, 
                         color = as.factor(Year))) +
  geom_segment(aes(xend = Group, y = 0, yend = total_import), linewidth = 1) +
  geom_point(size = 4) +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Giá trị xuất khẩu theo nhóm mặt hàng",
       x = "Mặt hàng", y = "Giá trị xuất khẩu (USD)", color = "Năm") +
  theme_minimal()

# ====== DỮ LIỆU IMPORT ======
# Tính tổng nhập khẩu theo sản phẩm & năm
import_group <- data_export %>%
  filter(!is.na(Group)) %>%   # bỏ NA (dòng tổng quốc gia)
  filter(!grepl("TOTAL", Group, ignore.case = TRUE)) %>%  # bỏ các dòng ghi tổng mặt hàng
  mutate(Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Group, Year) %>%
  summarise(total_import = sum(Value, na.rm = TRUE), .groups = "drop")

# Vẽ stacked area chart
ggplot(import_group %>% filter(Group %in% c("Fibres, not spun", "Cotton fabrics", "Iron and steel")), 
       aes(x = reorder(Group, total_import), 
           y = total_import, 
           color = as.factor(Year))) +
  geom_segment(aes(xend = Group, y = 0, yend = total_import), 
               position = position_dodge(width = 0.6)) +
  geom_point(size = 3, position = position_dodge(width = 0.6)) +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Giá trị nhập khẩu theo nhóm mặt hàng",
       x = "Mặt hàng", y = "Giá trị nhập khẩu (USD)", color = "Năm") +
  theme_minimal()

###############################################
# Lấy top 10 mặt hàng nhập khẩu theo tổng giá trị cả năm
# Chuẩn bị dữ liệu
top_import2 <- top_import %>%
  arrange(desc(total_import_all_years)) %>%  # sắp xếp để lát vẽ theo chiều kim đồng hồ
  mutate(
    percent = total_import_all_years / sum(total_import_all_years),
    label_slice = paste0(round(percent*100, 1), "%"),  
    label_legend = paste0(Group, " (", comma(total_import_all_years), ")")
  )

# Đặt lại thứ tự factor theo đúng trình tự lát
top_import2$label_legend <- factor(top_import2$label_legend, 
                                   levels = top_import2$label_legend)

# Vẽ pie chart
ggplot(top_import2, aes(x = "", y = total_import_all_years, fill = label_legend)) +
  geom_col(width = 1, color = "white") +
  coord_polar(theta = "y", direction = -1) +   # -1 để quay theo chiều kim đồng hồ
  geom_text(aes(label = label_slice),
            position = position_stack(vjust = 0.5),
            color = "white", size = 4) +
  labs(title = "Top 10 mặt hàng xuất khẩu (tổng 3 năm)",
       fill = "Mặt hàng & giá trị") +
  theme_void() +
  theme(legend.position = "right")

###########################################
# Import dữ liệu
data_import <- read_csv("D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged.csv")
data_export <- read_csv("D:\\Download\\Data for subject\\DSR_cleaned\\Ex04_2022_2024_merged.csv")

# Chọn cột cần thiết và tính tổng giá trị theo Partner
import_edges <- data_import %>%
  filter(!is.na(Group), !grepl("TOTAL", Group, ignore.case = TRUE)) %>%
  mutate(Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Names) %>%
  summarise(weight = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  mutate(from = "Vietnam", to = Names)

export_edges <- data_export %>%
  filter(!is.na(Group), !grepl("TOTAL", Group, ignore.case = TRUE)) %>%
  mutate(Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Names) %>%
  summarise(weight = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  mutate(from = "Vietnam", to = Names)

library(igraph)
library(dplyr)
library(readr)

# Kết hợp Import + Export (nếu muốn vẽ cùng)
edges <- bind_rows(import_edges, export_edges)

# Tạo igraph object
net <- graph_from_data_frame(edges, directed = TRUE)

# Vẽ cơ bản với igraph
plot(net,
     edge.width = E(net)$weight / 1e6,  # scale cho dễ nhìn
     vertex.size = 15,
     vertex.color = "skyblue",
     vertex.label.cex = 0.8,
     edge.arrow.size = 0.5)


library(ggraph)

ggraph(net, layout = "fr") +  # Fruchterman-Reingold layout
  geom_edge_link(aes(width = weight), 
                 arrow = arrow(length = unit(4, 'mm')), 
                 end_cap = circle(3, 'mm'),
                 color = "gray") +
  geom_node_point(size = 6, color = "skyblue") +
  geom_node_text(aes(label = name), repel = TRUE) +
  scale_edge_width(range = c(0.5, 3)) +
  theme_void() +
  labs(title = "Vietnam Trade Network (Import & Export)")




# PHẦN 1: Chuẩn bị dữ liệu gốc (chỉ thay data_import bằng data_export nếu muốn vẽ xuất khẩu)
top_import <- data_export %>%
  filter(!is.na(Group)) %>%                                   # bỏ NA
  filter(!grepl("TOTAL", Group, ignore.case = TRUE)) %>%      # bỏ dòng tổng
  mutate(Value = as.numeric(gsub(",", "", X12_months_Value))) %>%
  group_by(Group) %>%
  summarise(total_import_all_years = sum(Value, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(total_import_all_years)) %>%
  slice_head(n = 10)   # lấy top 10

# PHẦN 2: Tạo biến phần trăm và label
top_import2 <- top_import %>%
  arrange(desc(total_import_all_years)) %>%
  mutate(
    percent = total_import_all_years / sum(total_import_all_years),
    label_slice = paste0(round(percent*100, 1), "%"),  
    label_legend = paste0(Group, " (", scales::comma(total_import_all_years), ")")
  )

# đảm bảo legend theo đúng thứ tự lát
top_import2$label_legend <- factor(top_import2$label_legend, 
                                   levels = top_import2$label_legend)

# PHẦN 3: Vẽ pie chart
library(ggplot2)

ggplot(top_import2, aes(x = "", y = total_import_all_years, fill = label_legend)) +
  geom_col(width = 1, color = "white") +
  coord_polar(theta = "y", direction = -1) +
  geom_text(aes(label = label_slice),
            position = position_stack(vjust = 0.5),
            color = "white", size = 4) +
  labs(title = "Top 10 mặt hàng xuất khẩu (tổng 3 năm)",
       fill = "Mặt hàng & giá trị") +
  theme_void() +
  theme(legend.position = "right")







################################################################################
library(dplyr)
library(stringr)

# ---- Thay đổi đường dẫn nếu file ở nơi khác
infile  <- "D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged.csv"
outfile <- "D:\\Download\\Data for subject\\DSR_cleaned\\Im05_2022_2024_merged_summary.csv"

# ---- Đọc dữ liệu
df <- read.csv(infile, stringsAsFactors = FALSE, check.names = FALSE)

# ---- Xác định cột
group_col <- names(df)[tolower(names(df)) == "group"][1]
name_col  <- names(df)[tolower(names(df)) == "names"][1]
fileid_col <- names(df)[tolower(names(df)) == "fileid"][1]

# ---- Danh sách các cột quantity
qty_cols <- names(df)[grepl("(?i)_quantity$", names(df), perl = TRUE)]

# ---- Chuyển các cột quantity về numeric
df[qty_cols] <- lapply(df[qty_cols], function(x) {
  as.numeric(gsub(",", "", as.character(x)))
})

# ---- Xác định các dòng Summary (Group bị NA hoặc trống)
is_summary_row <- is.na(df[[group_col]]) | trimws(df[[group_col]]) == ""

# ---- Với mỗi combination (Names, FileID), tính tổng quantity
for (nm in unique(df[[name_col]])) {
  for (yr in unique(df[[fileid_col]])) {
    mask_sub <- df[[name_col]] == nm & df[[fileid_col]] == yr &
      !(is.na(df[[group_col]]) | trimws(df[[group_col]]) == "")
    mask_sum <- df[[name_col]] == nm & df[[fileid_col]] == yr & is_summary_row
    
    if (any(mask_sub) & any(mask_sum)) {
      sums <- colSums(df[mask_sub, qty_cols, drop = FALSE], na.rm = TRUE)
      for (col in qty_cols) {
        df[mask_sum, col] <- sums[col]
      }
    }
  }
}

# ---- Thay NA/chuỗi rỗng trong Group bằng "Summary"
df[[group_col]][is_summary_row] <- "Summary"

# ---- Lưu kết quả
write.csv(df, outfile, row.names = FALSE)

cat("File đã lưu:", outfile, "\n")
