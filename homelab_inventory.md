# Homelab Inventory & Cloud Cost Comparison

This document provides a breakdown of the hardware resources in my homelab, along with their one-time costs and equivalent monthly costs if provisioned through major cloud providers.

The goal is to document the scale and value of the environment, highlight the trade-offs between on-prem and cloud resources, and provide a reference for others who are considering similar setups.

---

## Compute Resources

- **NUC 11** (i5-1145G7, 4C/8T, 32 GB RAM)  
  • 500 GB SATA SSD (OS)  
  • 1 TB NVMe 990 Pro (ZFS pool)  
  • 32 GB RAM (2×16 GB)

- **NUC 12** (i5-1240P, 12C/16T, 32 GB RAM)  
  • 1 TB SATA SSD (OS)  
  • 1 TB NVMe 990 Pro (ZFS pool)  
  • 32 GB RAM (2×16 GB)

- **Beelink EQi13 Pro** (i5-13500H, 12C/16T, 32 GB RAM)  
  • 500 GB NVMe SSD (OS, included)  
  • 1 TB NVMe 990 Pro (ZFS pool)  
  • 32 GB RAM (2×16 GB, included)

- **Raspberry Pi 5** (4C/4T, 8 GB RAM)  
  • 128 GB NVMe (boot + storage)  
  • Argon NEO 5 case  
  • Argon NVMe expansion board

- **Synology DS423+** (Celeron J4125, 4C/4T, 6 GB RAM)  
  • 2 × 12 TB HDD (24 TB raw, ~12 TB usable SHR)  
  • 2 × 400 GB NVMe (cache + fast volume)  
  • 4 GB Synology SODIMM  
  • DS423+ chassis

**Total:**

- vCPUs: 44 threads (~44 vCPUs equivalent)
- RAM: ~110 GB

---

## Storage Resources

1. **System & Utility Storage** (local + local-lvm)
    - NUC 11: 500 GB SATA SSD
    - NUC 12: 1 TB SATA SSD
    - Beelink: 500 GB NVMe SSD
    - Pi 5: 128 GB NVMe  
      **Total:** ≈ 2.2 TB

2. **ZFS Cluster Storage** (nvme-zfs, HA workloads)
    - NUC 11: 1 TB NVMe
    - NUC 12: 1 TB NVMe
    - Beelink: 1 TB NVMe  
      **Total:** ≈ 3 TB usable

3. **Bulk NAS Storage** (NFS + SHR overhead)
    - 24 TB raw HDD (≈12 TB usable SHR) + 0.8 TB NVMe  
      **Total:** ≈ 24.8 TB counted

---

## Homelab Hardware Cost (One-Time)

**NUC 11 (i5-1145G7, 32 GB RAM, 500 GB SATA, 1 TB NVMe)**

- Base unit: $160
- Samsung 870 EVO 500 GB SATA SSD (OS): $55
- Samsung 990 Pro 1 TB NVMe (ZFS): $90
- TEAMGROUP DDR4 32 GB (2×16 GB): $56  
  **Subtotal: $361**

**NUC 12 (i5-1240P, 32 GB RAM, 1 TB SATA, 1 TB NVMe)**

- Base unit: $374
- Samsung 860 EVO 1 TB SATA SSD (OS): $110
- Samsung 990 Pro 1 TB NVMe (ZFS): $90
- TEAMGROUP DDR4 32 GB (2×16 GB): $56  
  **Subtotal: $630**

**Beelink EQi13 Pro (i5-13500H, 32 GB RAM, 500 GB NVMe, 1 TB NVMe)**

- Unit (includes 32 GB RAM + 500 GB NVMe): $399
- Samsung 990 Pro 1 TB NVMe (ZFS): $90  
  **Subtotal: $489**

**Raspberry Pi 5 (8 GB RAM, 128 GB NVMe)**

- Raspberry Pi 5 board: $80
- Argon NEO 5 case: $20
- Argon NVMe expansion board: $20
- ORICO 128 GB NVMe SSD: $15  
  **Subtotal: $135**

**NAS (Synology DS423+ with HDD + NVMe + RAM)**

- Synology DS423+ chassis: $561
- 2 × Seagate IronWolf 12 TB HDD: $402
- 2 × Synology SNV3410 400 GB NVMe: $320
- Synology DDR4 4 GB SODIMM: $90  
  **Subtotal: $1,373**

**Networking**

- UniFi Express 7 Router: $214
- UniFi Flex Mini 2.5G (USW-Flex-2.5G-5): $53
- UniFi Flex 2.5G (USW-Flex-2.5G-8): $186  
  **Subtotal: $453**

**Power Infrastructure**

- CyberPower CPS1215RM PDU: $63
- APC BE600M1 UPS: $80  
  **Subtotal: $143**

**Total Known Spend:** ≈ $3,584

---

## Cloud Equivalent Cost (Monthly)

**Compute**

- AWS m6i.xlarge (4 vCPU, 16 GB RAM) ≈ $140.16/mo
- To match ~44 vCPU & ~110 GB RAM → ≈ 11 × m6i.xlarge
- **Compute cost:** ≈ $1,542/mo

**Storage**

1. System & Utility Storage (≈2.2 TB) → EBS gp3 @ $0.08/GB → ~$176/mo
2. ZFS Cluster Storage (≈3 TB) → EBS gp3 $240/mo (or io2 $375/mo)
3. Bulk NAS Storage (≈24.8 TB, mixed EFS & S3 split)
    - 7 TB on EFS ($0.30/GB) → $2,100/mo
    - 17.8 TB on S3 ($0.023/GB) → ≈ $409/mo
    - **Total NAS cost ≈ $2,509/mo**

**Grand Totals**

- ≈ $4,467–$4,632 per month

---

## 3-Year Equivalent Cloud Cost and Savings

**Gross cloud cost over 36 months**

- ≈ $160,812 to $166,752

**Estimated homelab operating cost over 36 months**

- Hardware: ≈ $3,584 one-time
- Electricity: ≈ $12–$13/mo → ≈ $432–$468 over 36 months
- **Total owner cost:** ≈ $4,016–$4,052

**Net savings versus cloud (36 months)**

- ≈ $156,760 to $162,700

---

## Cloud Cost Comparison Table

| Category                     | Resource Size  | AWS Service           | Monthly Cost  |
| ---------------------------- | -------------- | --------------------- | ------------- |
| **Compute**                  | 44 vCPU, 110GB | 11 × m6i.xlarge       | $1,542        |
| **System & Utility Storage** | 2.2 TB         | EBS gp3               | $176          |
| **ZFS Cluster Storage**      | 3 TB           | EBS gp3 / io2         | $240–$375     |
| **Bulk NAS Storage**         | 24.8 TB        | 7 TB EFS + 17.8 TB S3 | ≈ $2,509      |
| **Total**                    | –              | –                     | $4,467–$4,632 |
