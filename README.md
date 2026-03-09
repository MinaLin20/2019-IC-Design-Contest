# 2019 IC Design Contest Preliminary - Image Convolutional Circuit (CONV)

本專案實現了一個高效率的圖像卷積電路，此設計包含三層運算流程，實現了深度學習中基礎的卷積神經網路運算。

## 專案功能與架構
電路輸入為 64x64 的灰階圖像，處理流程共分為三層
* **Layer 0 (Convolutional & ReLU)**：輸入圖像先經 Zero-padding，接著進行 3x3 的卷積運算（使用 Kernel 0 與 Kernel 1），最後通過 ReLU 激活函數 
* **Layer 1 (Max-pooling)**：採用 2x2 的視窗與步幅 (Stride) 為 2 的規格進行最大池化運算 
* **Layer 2 (Flatten)**：將運算結果平坦化為 2048 個訊號值的序列並輸出 。

## 技術規格
* **資料格式**：全系統使用 20-bit 有號數（4-bit 整數 + 16-bit 小數）進行運算 
* **介面控制**：透過 `csel` 訊號選擇記憶體空間（L0、L1、L2），並利用 `crd` 與 `cwr` 控制讀寫時序 
* **同步機制**：採用 `ready` (輸入) 與 `busy` (輸出) 作為系統啟動與結束的握手訊號
  
## File List
以下是本專案目錄中的主要檔案及其功能說明：
* **CONV.v**: 核心 RTL 原始碼
* **testfixture.v**: 驗證環境，包含測試激勵 (Stimulus) 與結果比對邏輯。
* **dat_grad/**: 測試數據集，存放運算所需的輸入與預期輸出檔案。
* **CONV_syn.v / CONV_syn.sdf / CONV_syn.qor**: 合成後的門級網表 (Netlist)、對應的時序資訊檔案以及合成品質報告。
* **conv_scan.vg**: 經 DFT 插入Scan Chain後的最終網表。
* **dc_syn.tcl / dc_dft.tcl**: 自動化執行合成與 DFT 編譯的 TCL 腳本。

## 合成結果
本設計經 Synopsys Design Compiler 合成後，主要數據如下：

* **Cell Area**: 25920 um²
* **Clock cycle time**: 10 ns
* **Timing Status**: WNS: 0.00 (無時序違規)

## 標準設計與驗證流程 (Standard Design Flow)
### 1. RTL Simulation
驗證原始邏輯正確性，確認運算結果與 Golden Patterns (`dat_grad/`) 一致。
`ncverilog testfixture.v CONV.v`
### 2. Synthesis
將 RTL 設計轉換為邏輯閘網表，並進行時序與面積最佳化。
`dc_shell -f dc_syn.tcl`
### 3. DFT
插入Scan Chain以提升晶片生產後的檢測能力。
`dc_shell -f dc_dft.tcl`
### 4. Gate-Level 模擬 (Post-Synthesis Simulation)
驗證合成後的電路加入 SDF 時序資訊後的正確性。
`ncverilog testfixture.v conv_scan.vg -v tsmc090_neg.v +define+SDF`
