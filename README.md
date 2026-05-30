# SystemVerilog Verification — UART/FIFO 통합 시스템
📅 프로젝트 정보

* 진행 기간: 2026.02.23 ~ 2026.03.03
* 검증 대상: `FIFO` (Circular Buffer, DEPTH=16), `UART + FIFO 통합 경로`
* 기술 스택: `SystemVerilog`, `Vivado XSim`, `OOP Testbench (Class, Mailbox, Event)`

---

## 📝 프로젝트 개요
FIFO의 경계 조건(Full/Empty 동시 입출력)과 `uart_rx → FIFO_RX → FIFO_TX → uart_tx` End-to-End 데이터 무결성을 검증한 프로젝트입니다.
단순 기능 동작 확인을 넘어, **실제 운용에서 오류가 집중되는 엣지 케이스**와 **비동기 통신의 Baud Rate 허용 오차 한계**를 정량적으로 검증하는 데 집중했습니다.

---

## 🔑 주요 구현 내용

### 1. 계층형 Testbench 구조 (`gen → drv → mon → scb`)

* **Architecture**: Generator → Driver → DUT → Monitor → Scoreboard의 단방향 데이터 흐름으로 각 블록의 역할을 명확히 분리.
* **Timing Strategy**: Drive는 `posedge clk + 1ns`, Monitor는 `negedge clk` 기준으로 샘플링 시점을 분리하여 setup/hold margin 확보.
* **Scoreboard**: queue 기반으로 예상값을 추적하고, UART 검증에서는 `gen → scb` 직접 경로(`gen2scb`)를 별도 추가하여 원본 tx 데이터를 독립 queue에 저장 후 비교.

### 2. FIFO 경계 조건 검증

* **Boundary Scenario**: Empty/Full 상태에서 push & pop 동시 인가 시 설계 정책(Empty → push만 수행, Full → 신규 데이터 거부)이 올바르게 동작하는지 검증.
* **Random Test**: 8bit 전범위(0x00~0xFF) 랜덤 트랜잭션 256회 실행 → 실제 발생한 pop 119건 전수 비교.

### 3. UART Baud Rate 허용 오차 정량화

* **Problem Definition**: UART는 비동기 통신이므로 장비 간 Baud Rate 편차가 누적되어 비트 경계 오판독을 일으킬 수 있음. 이론 허용치(±3%)가 실제 DUT에서 어느 지점까지 유효한지 직접 측정.
* **Measurement**: 오차 범위를 ±4.17% / ±5.21% / ±6.25% 세 구간으로 나누어 253건의 트랜잭션에 대해 pass/fail 집계.
* **Result**: ±4.17% 이내에서 253/253 PASS, ±5.21%부터 MSB 방향 누적 오차로 비트 오판독 발생 시작. 실측 허용치가 이론값(±3%)보다 약 1.2%p 넓음을 확인.

---

## 🚀 문제 해결 (Troubleshooting)

### 1. RX/TX 비교 타이밍 불일치

* **문제**: RX monitor에서 `tr_rx.tx_done = uf_if.tx_done` 직접 할당으로 `tx_done`이 1로 유지되어 Scoreboard 비교 시점이 계속 트리거됨.
* **해결**: 직접 할당 제거 → `tx_done` 이벤트 기반 트리거로 전환하여 비교 시점을 명확히 분리.

### 2. Baud Rate 오차 과잉에서도 PASS 발생

* **문제**: Scoreboard의 참조 데이터(`tr.rx_data`)가 원본 송신값이 아닌 DUT RX 출력값을 참조 → 오류가 있어도 자기 자신과 비교하는 구조가 되어 오차 20%에서도 PASS.
* **해결**: `gen2scb` 경로를 별도로 추가하여 Generator에서 생성한 원본 데이터를 독립 queue(`uf_queue`)에 저장 후 비교.

---

## ✅ 검증 결과

| 모듈 | 결과 |
|------|------|
| FIFO 단독 | ✅ Generated 256 / Actual Pop 119 / **PASS 119 / FAIL 0** |
| UART + FIFO 통합 | ✅ **COMPARED 253 / PASS 253 / FAIL 0** |

Baud Rate 오차 허용 범위

| 오차 범위 | 결과 |
|-----------|------|
| ±4.17% | ✅ PASS 253 / FAIL 0 |
| ±5.21% | ⚠️ PASS 148 / FAIL 105 |
| ±6.25% | ❌ PASS 105 / FAIL 148 |

---

## 📚 배운점

* **Testbench Architecture**: 블록 간 역할을 명확히 분리하면 버그 원인이 어느 레이어에 있는지 즉시 좁혀낼 수 있다는 것을 직접 경험. Scoreboard의 참조 데이터 오류처럼 구조 설계 실수는 기능 버그보다 발견이 늦어짐.
* **Timing in Simulation**: Drive/Monitor 타이밍 분리가 단순한 규칙이 아니라 setup/hold 마진 확보를 위한 필수 전략임을 이해. 잘못된 샘플링 시점 하나가 전체 검증 신뢰성을 무너뜨릴 수 있음.
* **Async Communication Verification**: 비동기 시스템은 "동작한다"를 넘어 "어디까지 동작한다"를 정량화하는 것이 검증의 핵심. 이론 스펙과 실측값의 차이를 직접 수치로 확인하는 경험을 쌓음.

---

## 🖥️ 개발 환경

| 항목 | 내용 |
|------|------|
| HDL | SystemVerilog (IEEE 1800) |
| EDA Tool | Xilinx Vivado |
| 시뮬레이터 | Vivado Simulator (XSim) |
| 타겟 클럭 | 100MHz |

