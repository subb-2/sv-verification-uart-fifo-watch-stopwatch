# SystemVerilog Verification (UART/FIFO & Stopwatch/Clock)

> - **Verification Method:** OOP 기반 SystemVerilog Testbench (Class, Mailbox, Event)
> - **Target:** UART + FIFO 통합 시스템, Stopwatch / Clock 디지털 회로
> - **Language:** SystemVerilog

---

## 📌 프로젝트 개요

UART + FIFO 통합 시스템과 Stopwatch/Clock 디지털 회로에 대한 **SystemVerilog 기반 Testbench**를 설계하여,
계층적 블록 구조(Generator → Driver → Monitor → Scoreboard)로 기능 검증을 수행하는 프로젝트입니다.
각 모듈의 단독 검증뿐만 아니라 두 시스템의 통합 검증(Integration Verification)까지 포함합니다.

---

## 🏗️ Testbench 구조

모든 검증 환경은 공통적으로 아래 블록 구조를 따릅니다.

| 블록 | 역할 |
|------|------|
| `gen` | 시나리오 및 랜덤 입력 생성 |
| `drv` | clk에 맞춰 DUT에 신호 전달 |
| `mon` | DUT 출력 Data Sampling |
| `scb` | queue 기반 데이터 비교 및 pass/fail count |
| `interface` | DUT 신호 연결 |

Drive는 `posedge clk` 기준, Monitor는 `negedge clk` 기준으로 안정된 값을 샘플링합니다.

---

## 🎯 검증 대상 및 시나리오

### Part 1 — FIFO (김수빈)

circular buffer 구조의 FIFO (DEPTH=16, BIT_WIDTH=8)를 검증합니다.  
Full/Empty 경계 상태와 동시 입출력(push & pop) 처리 정책을 중점적으로 검증하였습니다.

| 시나리오 | 내용 |
|---------|------|
| **1** | Empty 상태 동시 입출력 → push만 수행, 0번지 저장 확인 |
| **2** | 16개 data push → Full = 1 확인 |
| **3** | Full 상태 동시 입출력 → 신규 data 저장 안 됨 확인 |
| **4** | 완전 비우기 (pop × 16) → Empty = 1, 순서 일치 확인 |
| **5** | Random Test 256회 (8bit 전체 범위) |

### Part 2 — UART + FIFO Integration (김수빈)

`uart_rx → FIFO_RX → FIFO_TX → uart_tx` 경로의 end-to-end 데이터 무결성과 BAUD RATE 허용 오차 범위를 검증합니다.

| 시나리오 | 비교 대상 |
|---------|---------|
| RX 값이 FIFO를 제대로 통과했는지 | UART RX 입력 = `tx_fifo_pop_data` |
| RX 값이 UART TX를 제대로 통과했는지 | UART RX 입력 = `tx_data` |
| BAUD RATE 허용 오차 범위 확인 | 이론 ±3% 기준, 3가지 범위 검증 |

### Part 3 — Stopwatch (하지훈)

100MHz 클럭 환경, 10ms 단위 카운트, Up/Down 모드 전환, Run/Stop/Clear 동작, 롤오버(00:00:00.00 ↔ 99:59:59.99)를 검증합니다.

### Part 4 — Clock (하지훈)

100MHz 클럭 환경, Time-set 모드 진입 시 시간 정지, Up/Down/Next 버튼 시간 변경, 롤오버(23:59:59.99 → 00:00:00.00)를 검증합니다.

### Part 5 — Integration (하지훈)

공유 시스템 클럭으로 Stopwatch, Clock 동시 동작 시 데이터 무결성 및 독립성을 검증합니다.  
Fault Injection Test(LSB 1bit 반전)로 Scoreboard의 오류 검출 능력을 추가 확인하였습니다.

---

## ✅ 검증 결과

| 모듈 | 결과 |
|------|------|
| FIFO 단독 | ✅ **PERFECT SUCCESS** — Generated 256 / Actual Pop 119 / PASS 119 / FAIL 0 |
| UART + FIFO 통합 | ✅ COMPARED 253 / FINAL PASS 253 / FAIL 0 |
| Stopwatch | ✅ PASS 51 / FAIL 0 / **COVERAGE 100%** |
| Clock | ✅ PASS 49 / FAIL 0 / **COVERAGE 100%** |
| Integration + Fault Injection | ✅ SW PASS 195 / CLK PASS 60 / **COVERAGE 100%** / 오류 검출 정상 |

**BAUD RATE 허용 오차 검증 결과**

| 오차 범위 | 결과 |
|---------|------|
| ±4.17% | ✅ PASS 253 / FAIL 0 |
| ±5.21% | ⚠️ PASS 148 / FAIL 105 |
| ±6.25% | ❌ PASS 105 / FAIL 148 |

---

## 🐛 Trouble Shooting

### 1. RX Data / TX Data 비교 FAIL (UART)
**원인**: RX monitor에서 `tr_rx.tx_done`이 계속 1로 유지되어 비교 순간이 어긋남.  
**해결**: `tr_rx.tx_done = uf_if.tx_done` 직접 할당 제거 → `tx_done` 이벤트 기반 조건 분리.

### 2. BAUD RATE 오차 범위 초과 시에도 PASS 발생 (UART)
**원인**: scb의 `tr.rx_data`가 PC가 보낸 원본 데이터가 아닌 DUT RX에서 온 DATA를 참조.  
**해결**: gen2scb 경로를 통해 원본 tx 데이터를 별도 queue(`uf_queue`)에 저장 후 비교.

### 3. 동시 입력에 의한 Clear 오동작 (Stopwatch)
**원인**: Run & Clear 동시 입력 시 Clear가 활성화되는 조건 미처리.  
**해결**: DUT의 동시 입력 처리 조건 개선 (`clear_en = clear & ~run_en & ~run_stop`).

### 4. Time-set 모드 진입과 시간 변경 펄스 동시 인가 시 불일치 (Clock)
**원인**: sw_time_set 엣지와 btn 입력이 동일 클럭 사이클에 발생.  
**해결**: 스코어보드 예외 처리 코드 추가.

---

## 🖥️ 개발 환경

| 항목 | 내용 |
|------|------|
| HDL | SystemVerilog (IEEE 1800) |
| EDA Tool | Xilinx Vivado |
| 시뮬레이터 | Vivado Simulator (XSim) |
| 타겟 클럭 | 100MHz |
