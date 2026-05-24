# SystemVerilog Verification
# (UART/FIFO & Stopwatch/Clock)

> SystemVerilog 기반 기능 검증 환경 구축 프로젝트  
> 발표자: 김수빈 (UART/FIFO), 하지훈 (Stopwatch/Clock)

---

## 📌 프로젝트 개요

UART + FIFO 통합 시스템과 Stopwatch/Clock 디지털 회로에 대한 **SystemVerilog 기반 Testbench**를 설계하여,  
계층적 블록 구조(Generator → Driver → Monitor → Scoreboard)로 기능 검증을 수행하는 프로젝트입니다.  
각 모듈의 단독 검증뿐만 아니라 두 시스템의 통합 검증(Integration Verification)까지 포함합니다.

---

## 📁 파일 구성

```
├── fifo.v                    # FIFO DUT (register_file + control_unit)
├── uart_top.v                # UART Top DUT (uart_rx, uart_tx, fifo_rx, fifo_tx, baud_tick)
└── tb_uart_fifo_sv.sv        # UART + FIFO SystemVerilog Testbench (OOP 기반)
```

---

## 🔷 Part 1 — FIFO Verification (김수빈)

### FIFO 설계 개요

```
         CLK
          │
  Reset ──┤
          │
wdata ───►│  ┌──────────────────┐  ├──► rdata
  push ───►│  │   register_file  │  │
   pop ───►│  │  (circular buf)  │  ├──► full
          │  └──────────────────┘  └──► empty
          │        control_unit
```

| 포트 | 방향 | 설명 |
|------|------|------|
| `clk` | input | 시스템 클럭 |
| `rst` | input | 비동기 리셋 (active high) |
| `push` | input | 데이터 쓰기 요청 |
| `pop` | input | 데이터 읽기 요청 |
| `push_data[7:0]` | input | 쓰기 데이터 |
| `pop_data[7:0]` | output | 읽기 데이터 |
| `full` | output | FIFO 가득 참 표시 |
| `empty` | output | FIFO 비어 있음 표시 |

**파라미터**

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `DEPTH` | 4 | FIFO 깊이 (슬롯 수), 이 프로젝트에서는 16으로 운용 |
| `BIT_WIDTH` | 8 | 데이터 비트 폭 |

**동시 입출력(push & pop) 처리 정책**

| 상태 | 동작 |
|------|------|
| Full + push & pop | pop만 수행 (신규 데이터 저장 안 함) |
| Empty + push & pop | push만 수행 (pop 무시) |
| 그 외 push & pop | wptr, rptr 동시 증가 |

### FIFO 검증 시나리오

| 시나리오 | 내용 |
|---------|------|
| **1** | 리셋 직후 Empty 상태에서 push & pop 동시 입력 |
| **2** | 16개 data 순차 push → Full = 1 확인 |
| **3** | Full 상태에서 push & pop 동시 입력 → 신규 data 저장 안 됨 확인 |
| **4** | FIFO 완전히 비우기 (pop × 16) → Empty = 1 확인 |
| **5** | 256회 Random Test (8bit 전체 범위) |

### Testbench 블록 구성 (FIFO)

```
  ┌─────────────────────────────────────────────────┐
  │                    EVENT                        │
  │  ┌──────────┐              ┌──────────────────┐ │
  │  │   gen    │──gen2drv───►│      drv         │ │
  │  │          │              │  preset()        │ │
  │  │full_fifo()│             │  push() / pop()  │ │
  │  │empty_fifo│             │  run()           │ │
  │  │simultaneous│           └────────┬─────────┘ │
  │  │randomize()│                     │            │
  │  └────┬─────┘              ┌───────▼──────────┐ │
  │       │ gen2scb             │    interface     │ │
  │       ▼                    └───────┬──────────┘ │
  │  ┌──────────┐                      │            │
  │  │   scb    │◄──mon2scb────┌───────▼──────────┐ │
  │  │ queue저장│               │      mon         │ │
  │  │ data비교 │               │ @(negedge clk)   │ │
  │  │pass/fail │               │ push/pop/wdata   │ │
  │  └──────────┘               │ rdata/full/empty │ │
  │                             └──────────────────┘ │
  └─────────────────────────────────────────────────┘
```

| 블록 | 역할 |
|------|------|
| `gen` | full, empty, simultaneous, randomize 시나리오 생성 |
| `drv` | 초기화 및 clk에 맞춰 push, pop, wdata 신호 전달 |
| `mon` | `@(negedge clk)` 기준 Data Sampling |
| `scb` | queue 기반 데이터 비교 및 pass/fail count |
| `interface` | DUT 신호 연결 및 SVA assertion |

**Drive/Monitor 타이밍**

```
       posedge clk        negedge clk
           │                   │
   Drive ──┤                   │
   (신호 인가)                  │
                        Monitor─┤
                        (안정된 값 샘플링)
```

### FIFO 검증 결과

| 시나리오 | 결과 |
|---------|------|
| Empty 동시 입출력 | ✅ PASS — data 0번지 저장 확인 |
| Full 채우기 (16개) | ✅ PASS — Full = 1 정상 확인 |
| Full 동시 입출력 | ✅ PASS — 신규 data 저장 안 됨, 기존 data 출력 |
| 완전 비우기 | ✅ PASS — 전체 16개 순서 일치 |
| Random (256회) | ✅ **PERFECT SUCCESS** — Generated: 256 / Actual Pop: 119 / PASS: 119 / FAIL: 0 |

---

## 🔷 Part 2 — UART + FIFO Integration Verification (김수빈)

### 시스템 구조

```
uart_rx ──► FIFO_RX ──► FIFO_TX ──► uart_tx
  │              │            │           │
rx_data    rx_fifo      tx_fifo      tx_data
           push_data    pop_data
```

```
clk ───►┌──────────────────────────────────────────────────┐
rst ───►│                   uart_top                       │
        │  ┌───────────┐  ┌─────────┐  ┌───────────────┐  │
uart_rx►│  │  U_UART_RX│  │U_FIFO_RX│  │  U_FIFO_TX    │  │
        │  └─────┬─────┘  └────┬────┘  └──────┬────────┘  │
        │   w_rx_data    w_rx_fifo        w_tx_fifo         │
        │                pop_data         pop_data          │
        │  ┌────────────────────────────────────────────┐  │
        │  │              U_UART_TX                     │  │──► uart_tx
        │  └────────────────────────────────────────────┘  │──► tx_done
        │  ┌──────────┐                                    │
        │  │U_BAUD_TICK│──────────────────────────────────►│ w_b_tick
        │  └──────────┘                                    │
        └──────────────────────────────────────────────────┘
```

### UART + FIFO 검증 시나리오

| 목적 | 비교 대상 |
|------|---------|
| Random RX 값이 FIFO를 제대로 통과했는지 확인 | UART RX 입력 = `tx_fifo_pop_data` |
| Random RX 값이 UART TX를 제대로 통과했는지 확인 | UART RX 입력 = `tx_data` |
| BAUD RATE 허용 오차 범위 확인 | UART RX 입력 = `tx_data` |

### Testbench 블록 구성 (UART)

| 블록 | 역할 |
|------|------|
| `gen` | 랜덤 rx_data 생성 (constraint: `rx_data != 8'h00`) |
| `drv` | UART 비트 직렬 전송, 리셋 제어, baud rate 가변 |
| `mon` | `rx_done` / `tx_done` / `tx_start` 기준 Data Sampling |
| `scb` | queue 기반 비교 및 pass/fail count (INTERNAL / FINAL) |

**Drive/Monitor 타이밍**

```
[Drive 시점]   posedge 이후 1ns
[Monitor 시점] 신호가 1로 변한 기준 negedge
```

### BAUD RATE 허용 오차 검증

> UART는 비동기 통신이므로 Baud Rate 차이에 의한 타이밍 오차 누적이 데이터 오류를 유발  
> 이론상 허용 오차: **±3%**

| 오차 범위 | constraint 설정 | 결과 |
|---------|----------------|------|
| ±4.17% | `baud_scale inside {[9200:10000]}` | ✅ PASS 253 / FAIL 0 |
| ±5.21% | `baud_scale inside {[9100:11000]}` | ⚠️ PASS 148 / FAIL 105 |
| ±6.25% | `baud_scale inside {[9000:12000]}` | ❌ PASS 105 / FAIL 148 |

**오차 발생 원인**: 통신 속도 증가/감소 → 타이밍 오차 누적 → 비트 샘플링 포인트 이탈

```
예) 3e = 0011_1110  (정상 수신 기대)
    be = 1011_1110  (오차 5.64% 시 실제 수신)
    → MSB 샘플링 시점에서 PC가 보내는 신호가 빨라져 비트가 밀림
```

### Trouble Shooting

**[1] RX Data / TX Data 비교 FAIL**

- **원인**: RX monitor에서 `tr_rx.tx_done`이 계속 1로 유지되어 비교 순간이 어긋남  
- **해결**: `tr_rx.tx_done = uf_if.tx_done` 직접 할당 제거 → `tx_done` 이벤트 기반 조건 분리

**[2] BAUD RATE 오차 범위 초과 시에도 PASS 발생**

- **원인**: scb의 `tr.rx_data`가 PC가 보낸 원본 데이터가 아닌 DUT RX에서 온 DATA를 참조  
- **해결**: gen2scb 경로를 통해 원본 tx 데이터를 별도 queue(`uf_queue`)에 저장 후 비교

### UART + FIFO 검증 결과

```
====  UART + FIFO VERIFICATION  ====
  Total test cnt      =      256
  COMPARED cnt        =      253
  INTERNAL pass cnt   =      256
  INTERNAL fail cnt   =        0
  FINAL pass cnt      =      253
  FINAL fail cnt      =        0
====================================
```

---

## 🔶 Part 3 — Stopwatch Verification (하지훈)

### Stopwatch 설계 개요

100MHz 클럭 환경에서 동작하는 스톱워치 시스템입니다.

| 항목 | 내용 |
|------|------|
| 카운트 단위 | 10ms (100Hz Tick) |
| 카운트 모드 | Up / Down 전환 가능 |
| 버튼 기능 | Run/Stop (토글), Clear |
| 측정 범위 | 00:00:00.00 ~ 99:59:59.99 |
| 구조 | Tick Gen → msec → sec → min → hour (캐리 전파) |

**Clear 우선순위 정책**

```
wire clear_en = clear & ~run_en & ~run_stop;
```

> Run/Stop > Clear — 동시 입력 시 Clear 무시, Stop 상태에서만 Clear 작동

### Stopwatch 검증 시나리오

| 테스트 | 내용 |
|-------|------|
| **Test 1.1** | Run/Stop, Clear 버튼 동작 확인 (입력 확률 run/stop=50%, clear=20%, 간격 20ms, 총 2s) |
| **Test 1.2** | Clear 버튼 동작 조건 확인 — 동시 입력 시 Clear 무시, Stop 상태에서만 작동 |
| **Test 2.1** | Count Mode 변경 테스트 (토글 간격 200ms, 총 2s) |
| **Test 2.2** | 롤오버 테스트 — 00:00:00.00 → 99:59:59.99 → 00:00:00.00 경계 구간 반복 |
| **Test 3** | Full case 테스트 — Coverage 기반 모든 버튼 조합 검증 (coverage = 100%) |

### Stopwatch 검증 결과

| 테스트 | 결과 |
|-------|------|
| Test 1.1 | ✅ PASS=73 / FAIL=0 — Run/Stop 및 Clear 동작 확인 |
| Test 1.2 | ✅ PASS=58 / FAIL=0 — 입력 우선순위 Run/Stop > Clear 확인 |
| Test 2.1 | ✅ PASS=11 / FAIL=0 — Mode=0 up count, Mode=1 down count 확인 |
| Test 2.2 | ✅ PASS=12 / FAIL=0 — 롤오버 정상 동작 확인 |
| Test 3 | ✅ PASS=51 / FAIL=0 / **COVERAGE=100%** |

---

## 🔶 Part 4 — Clock Verification (하지훈)

### Clock 설계 개요

100MHz 클럭 환경에서 동작하는 디지털 시계 시스템입니다.

| 항목 | 내용 |
|------|------|
| 카운트 단위 | 10ms (100Hz Tick) |
| 시간 설정 모드 | Time-set (sw_time_set) — Up/Down/Next sel |
| 측정 범위 | 00:00:00.00 ~ 23:59:59.99 |
| Next 버튼 | 시간 변경 자리 선택 순환 (sel[1:0]: 00→01→10→11) |
| 동시 입력 처리 | Up & Down 동시 입력 무시 (Up 또는 Down 우선) |

### Clock 검증 시나리오

| 테스트 | 내용 |
|-------|------|
| **Test 1.1** | Time-set 모드 진입 시 시간 정지 확인 (모드 토글 주기 100~300ms) |
| **Test 1.2** | Up/Down/Next 버튼 시간 변경 동작 확인 (각 25%, 간격 20ms, 총 2s) |
| **Test 1.3** | Up/Down/Next 동시 입력 동작 확인 — Down & Next 시 Down 우선, Up & Down 무시 |
| **Test 2** | 롤오버 테스트 — 23:59:59.90 → 00:00:00.10 경계 구간 10회 반복 |
| **Test 3** | Full case — Coverage 기반 모든 조합 검증 (coverage = 100%) |

### Clock 검증 결과

| 테스트 | 결과 |
|-------|------|
| Test 1.1 | ✅ PASS=11 / FAIL=0 — Time-set 모드 진입 시 시간 정지 확인 |
| Test 1.2 | ✅ PASS=100 / FAIL=0 — 시간 변경 기능 확인 |
| Test 1.3 | ✅ PASS=63 / FAIL=0 — Up, Down 우선 입력, Up & Down 동시 무시 확인 |
| Test 2 | ✅ 10회 경계 구간 정상 동작 확인 |
| Test 3 | ✅ PASS=49 / FAIL=0 / **COVERAGE=100%** |

---

## 🔶 Part 5 — Integration Verification (하지훈)

### 통합 검증 전략

공유 시스템 클럭으로 Stopwatch, Clock 동시 동작 시 데이터 및 독립성 확인

- 모드 기반 가변 확률 적용 (Time-set 모드: 시간 설정 버튼 입력 확률 증가)
- 입력 간격 20ms, 카운트 방향 up/down 랜덤 토글 (100~500ms)
- Time-set 모드 랜덤 토글 (200~1000ms)
- Coverage를 통한 버튼 개별 입력 및 스위치 조합 케이스 확인

### 통합 검증 결과

```
========== SUMMARY ==========
STOPWATCH: PASS=195  FAIL=0
CLOCK    : PASS=60   FAIL=0
BTN COUNT: run_stop=45  clear=35  up=29  down=42  next=38
SW TOGGLE: cnt_mode=30  sw_time_set=14
COVERAGE : 100.00%
==============================
```

### Fault Injection Test

- DUT 출력의 LSB 1bit를 반전시켜 Scoreboard 오류 검출 능력 확인
- 결과: STOPWATCH PASS=0 / FAIL=37, CLOCK PASS=0 / FAIL=37 → 오류 정상 검출

### Trouble Shooting

**[1] Stopwatch — 동시 입력에 의한 Clear 오동작**

- **원인**: Run & Clear 동시 입력 시 Clear가 활성화되는 조건 미처리  
- **해결**: DUT의 동시 입력 처리 조건 개선 (`clear_en = clear & ~run_en & ~run_stop`)

**[2] Clock — Time-set 모드 진입과 시간 변경 펄스 동시 인가 시 불일치**

- **원인**: sw_time_set 엣지와 btn 입력이 동일 클럭 사이클에 발생  
- **해결**: 스코어보드 예외 처리 코드 추가

---

## 🖥️ 개발 환경

| 항목 | 내용 |
|------|------|
| HDL | SystemVerilog (IEEE 1800) |
| Verification | OOP 기반 Testbench (Class, Mailbox, Event) |
| EDA Tool | Xilinx Vivado |
| 시뮬레이터 | Vivado Simulator (XSim) |
| 타겟 클럭 | 100MHz |

---

## ✅ 전체 검증 항목 요약

| 모듈 | 시나리오 | 최종 결과 |
|------|---------|---------|
| FIFO 단독 | Empty/Full/동시/랜덤 (256회) | ✅ PERFECT SUCCESS |
| UART + FIFO 통합 | FIFO 통과 확인, TX 통과 확인, BAUD RATE 오차 | ✅ PASS 253/253 |
| Stopwatch | Run/Stop/Clear/모드/롤오버/Full case | ✅ COVERAGE 100% |
| Clock | Time-set/Up/Down/Next/롤오버/Full case | ✅ COVERAGE 100% |
| Integration | Stopwatch + Clock 동시 동작 + Fault Injection | ✅ COVERAGE 100% |
