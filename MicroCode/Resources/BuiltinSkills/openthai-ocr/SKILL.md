---
name: openthai-ocr
description: High-precision Thai + English OCR and structured Markdown/HTML table extraction powered by OpenThai 2.0 OCR (`OpenThai2.0-OCR-Text` 4.2MB ONNX CPU + `OpenThai2.0-OCR-Markdown` 0.63B). Use whenever reading Thai/English scanned PDFs, government documents, Royal Gazette, budget tables, invoices, receipts, forms with merged cells (`rowspan`/`colspan`), or Thai UI screenshots.
---

# OpenThai 2.0 OCR Skill (`openthai_ocr`)

MicroCode bundles **OpenThai 2.0 OCR** (`https://openthai.ai/openthai2p0-ocr`, Apache-2.0) directly inside the IDE and fuses it into `UniversalAttachmentEngine`, `AppleVisionEngine`, and `NativeComputerUseService`.

## Two Specialized Engines

1. **`OpenThai 2.0 OCR Text` (`mode: "text"` — Bundled 4.2 MB ONNX CPU Daemon)**
   - Runs **100% offline on CPU** (~150ms per Retina screenshot, ~390ms per dense A4 page) via a warm persistent daemon.
   - Achieves **99.5%** character accuracy on Thai Parliament Budget documents and **96.3%** on Royal Gazette scans, preserving Thai tone marks (`วรรณยุกต์`), floating vowels, auto-deskewing tilted scans, rotating 90°/180° pages, and outputting canonical normalized Thai Unicode (`thai_norm`).
   - Pass `"include_boxes": true` when exact 2D pixel/normalized line coordinates are needed for layout analysis or UI clicking.

2. **`OpenThai 2.0 OCR Markdown` (`mode: "markdown"` or `"auto"` — Structured Document & Table Parser)**
   - Extracts full document structure into **Markdown** while keeping complex Thai/English tables intact as **HTML `<table>` blocks** (`rowspan` / `colspan` when connected to a local `iapp/OpenThai2.0-OCR-Markdown` vLLM endpoint at `OPENTHAI_OCR_MARKDOWN_URL` / `http://127.0.0.1:8000/v1` or `IAPP_API_KEY`, and falling back offline to 2D spatial HTML table reconstruction over `OpenThai 2.0 OCR Text` boxes).

## Usage Examples

- **Extract structured Markdown & tables from a Thai PDF (pages 1–5)**:
  `{"path": "budget_2569.pdf", "mode": "markdown", "page_start": 1, "page_end": 5}`
- **Fast offline Thai+English line OCR with bounding boxes on a screenshot**:
  `{"path": "screen.png", "mode": "text", "include_boxes": true}`
