# VietNam Import & Export

## 1. Problem Definition & Understanding:
- This project looks at Vietnam’s export and import data to understand how the country trades with the rest of the world. 
- The aim is to organize and study this data to discover patterns, such as which products are traded the most, who the top export partners are, and how Vietnam’s exports have developed over time.

## 2. Data Collection:
- The Data collected from the website: "https://www.nso.gov.vn/en/import-export/"
- This file has the extension:  .xls
- To include: 6 files that have names like (E04-2022-11) and spanning from 2022 to 2024
- Raw name:
  -  E04 is the exporting + year
  -  E05 is the importing + year

## 3. Data Preprocessing:
- The first, we are going to make clean the data (Changing from E04-2022-11 to  E04-2022-11 _cleaned and similar with other files) and the extension file has been converted to <b>".csv"</b> (be intuitive to use)
  - Before processing data: [Data_raw/E04-2022-11.xls](https://github.com/Xenko2005/VietNam-Import-Export/blob/dad156ced97b9e7f18ee094b09614338d3c01d85/Data_raw/E04-2022-11.xls) 
  - After processing data: [Data_cleaned/Ex04-2022-11_clean.csv](https://github.com/Xenko2005/VietNam-Import-Export/blob/dad156ced97b9e7f18ee094b09614338d3c01d85/Data_cleaned/Ex04-2022-11_clean.csv)
- The next, we are going to merge 6 files cleaned data of exporting and importing into 2 files
  - The Export data: [Ex04_2022_2024_merged.csv](https://github.com/Xenko2005/VietNam-Import-Export/blob/dad156ced97b9e7f18ee094b09614338d3c01d85/Data_cleaned/Ex04_2022_2024_merged.csv)
  - The Import data: [Im05_2022_2024_merged.csv](https://github.com/Xenko2005/VietNam-Import-Export/blob/dad156ced97b9e7f18ee094b09614338d3c01d85/Data_cleaned/Im05_2022_2024_merged.csv)
- We add more 2 columns to identify importing and exporting followed by years and File ID
  - File ID: 1 → 2022, 2 → 2023, 3 → 2024

## 4. Prophet Model:
- In this project, we use the Prophet model developed by Facebook (Meta)
Prophet is a time series forecasting model that works well with data that has
trend and seasonal patterns.

$$
y(t) = g(t) + s(t) +h(t) + \varepsilon_t
$$

Where:
  - $g(t)$ represents the trend (long-term increase or decrease)
  - $s(t)$ represents the seasonality (repeating patterns such as months or years)
  - $h(t)$ can include holiday effects or special events
  - $\varepsilon_t$ is random noise
### 4.1. Comprehension about Trend Modeling - $g(t)$

### Fake Monthly Export Data 

| Month | Export (VND) |
|------:|-------------:|
| 1 | 100 |
| 2 | 120 |
| 3 | 130 |
| 4 | 150 |
| 5 | 170 |
| 6 | 190 |
| 7 | 210 |
| 8 | 240 |
| 9 | 260 |
| 10 | 280 |
| 11 | 300 |
| 12 | 320 |

#### 1. Base Trend $g_0(t)$
- Prophet first fits a simple straight line for all data:

$$g(t) = k \cdot t + m$$

For example:
- $k = 20$ (growth per month)  
- $m = 80$ (starting point)

This represents slow growth from month 1 to 6.

#### 2. Changepoint ($t_j$)
- Prophet checks where the error increases and finds a changepoint, here at
month 7.

- After this point, Prophet allows the slope (k) to change:

$$k_{\text{new}} = k + \delta_1$$

- If $\delta_1 = +10$, then the new slope $k_{\text{new}} = 20 + 10 = 30$

=> The trend becomes steeper after month 7.

#### 3. Offset Correction (γ)

- When the slope changes, the line can “jump” at the changepoint.  
- Prophet adds $γ₁$ (gamma) to move the line up or down, keeping it smooth and  
continuous.

$$
y₁ = −δ₁ ⋅ t₁
$$

With $δ₁ = +10$ and $t₁ = 7$ → $γ₁ = -70$.

=> So Prophet corrects the intercept by $-70$ to keep the two parts connected.

#### 4. Final Trend Function

The complete trend is:

$$
g(t) = k + a(t)δt + m + a(t)⋅y
$$

where $a(t)$ is $0$ before month $7$ and $1$ after month $7$.

• For $t < 7$: $g(t) = 20⋅t + 80$  
• For $t ≥ 7$: $g(t) = (20 + 10)⋅t + (80 – 70) = 30⋅t + 10$  

- Before month $7$: slow growth (+20 per month)
- After month $7$: faster growth (+30 per month)

- Both lines meet smoothly at month $7$.

### 4.2. Comprehension about Seasonality Modeling – $s(t)$

#### 1. Build the formula

- With period $P = 12$ and $N = 1$ (Fourier series)

$$y_t = a_1 \cos\left(\frac{2\pi t}{12}\right) + b_1 \sin\left(\frac{2\pi t}{12}\right) + \varepsilon_t$$

**Goal:**  
Find $a_1$ and $b_1$ that make the **Loss** (error) as small as possible:

$$L(a_1, b_1)=\sum_{t=1}^{12}\left(y_t- a_1 \cos\left(\frac{2\pi t}{12}\right)- b_1 \sin\left(\frac{2\pi t}{12}\right) \right)^2$$

#### 2. Matrix form

We can write this as a matrix equation:

$$
y =
\begin{bmatrix}
y_1 \\
y_2 \\
\vdots \\
y_{12}
\end{bmatrix},
\quad
X =
\begin{bmatrix}
\cos\left(\frac{2\pi \cdot 1}{12}\right) & \sin\left(\frac{2\pi \cdot 1}{12}\right) \\
\cos\left(\frac{2\pi \cdot 2}{12}\right) & \sin\left(\frac{2\pi \cdot 2}{12}\right) \\
\vdots & \vdots \\
\cos\left(\frac{2\pi \cdot 12}{12}\right) & \sin\left(\frac{2\pi \cdot 12}{12}\right)
\end{bmatrix}
$$

Then the best coefficients are found by:

$$\begin{bmatrix}
a_1 \\ 
b_1 \\ \end{bmatrix}=(X^T X)^{-1} X^T y$$

#### 3. Calculation result

- Using linear regression:  

  $a_1 = 25.39$, $b_1 = -77.75$

- So, the seasonal function is:

$$s(t) = 25.39 \cos\left(\frac{2\pi t}{12}\right) -  77.75 \sin\left(\frac{2\pi t}{12}\right)$$

#### 4. Compute Loss (SSE)

$$L = \sum_{t=1}^{12} \left(y_t - s(t)\right)^2 = 36,095.55$$

- This is the minimum error Prophet can reach using the two parameters $a_1$ and $b_1$.

- If more harmonics are added ($N = 2, 3, \dots$), Prophet will have more parameters → more complex seasonal path → loss decreases.

- $N$ = number of seasonal waves (pairs of sine and cosine).

### 4.3. Comprehension about Holiday & Events – $h(t)$
 
- In Prophet, $h(t)$ represents the **effect of holidays or special events** on the forecast.

$$h(t) = \sum_{i=1}^{L} \delta_i \cdot D_i(t)$$

Where:  
  - $L$ – number of holidays or events.  
  - $D_i(t)$ – dummy variable: 
    - $D_i(t) = 1$ if time $t$ is within event $i$,  
    - $D_i(t) = 0$ otherwise.  

- $\delta_i$ – the estimated impact of event $i$ on $y(t)$,  learned by Bayesian regression.  

  - If $\delta_i > 0$ → the event increases $y(t)$.  
  - If $\delta_i < 0$ → the event decreases $y(t)$.

#### Example

- Suppose there are 12 months with **two events**:  
  - **January**: New Year → increases by 20  
  - **August**: Trade Fair → increases by 15  

Then:

$$
D_1(t) =
\begin{cases}
1 & \text{if } t = 1 \\
0 & \text{otherwise}
\end{cases}
\qquad
D_2(t) =
\begin{cases}
1 & \text{if } t = 8 \\
0 & \text{otherwise}
\end{cases}
$$

With $\delta_1 = 20$ and $\delta_2 = 15$:

$$h(t) = 20 \cdot D_1(t) + 15 \cdot D_2(t)$$

- When $t = 1$ → $h(1) = 20$  
- When $t = 8$ → $h(8) = 15$  
- For other months → $h(t) = 0$








