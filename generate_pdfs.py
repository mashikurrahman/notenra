import os
import subprocess
import sys

def convert_md_to_html(md_path, html_path, title, subtitle):
    with open(md_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    html_content = []
    in_table = False
    table_rows = []
    in_code_block = False
    code_lines = []

    for line in lines:
        raw = line.rstrip('\r\n')
        
        # Handle code blocks
        if raw.startswith('```'):
            if in_code_block:
                in_code_block = False
                code_text = '\n'.join(code_lines)
                html_content.append(f'<pre><code>{code_text}</code></pre>')
                code_lines = []
            else:
                in_code_block = True
                code_lines = []
            continue
        
        if in_code_block:
            safe_line = raw.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            code_lines.append(safe_line)
            continue

        # Handle tables
        if raw.startswith('|') and raw.endswith('|'):
            cells = [c.strip() for c in raw.strip('|').split('|')]
            if all(c.replace('-', '').replace(':', '') == '' for c in cells):
                continue # separator row
            if not in_table:
                in_table = True
                table_rows.append(('header', cells))
            else:
                table_rows.append(('row', cells))
            continue
        else:
            if in_table:
                in_table = False
                t_html = ['<table>']
                for r_type, cells in table_rows:
                    tag = 'th' if r_type == 'header' else 'td'
                    row_str = '<tr>' + ''.join(f'<{tag}>{c}</{tag}>' for c in cells) + '</tr>'
                    t_html.append(row_str)
                t_html.append('</table>')
                html_content.append('\n'.join(t_html))
                table_rows = []

        if raw.startswith('# '):
            html_content.append(f'<h1>{raw[2:]}</h1>')
        elif raw.startswith('## '):
            html_content.append(f'<h2>{raw[3:]}</h2>')
        elif raw.startswith('### '):
            html_content.append(f'<h3>{raw[4:]}</h3>')
        elif raw.startswith('#### '):
            html_content.append(f'<h4>{raw[5:]}</h4>')
        elif raw.startswith('* ') or raw.startswith('- '):
            text = raw[2:]
            # formatting bold and inline code
            text = format_inline(text)
            html_content.append(f'<li>{text}</li>')
        elif raw.strip() == '---':
            html_content.append('<hr/>')
        elif raw.strip() == '':
            html_content.append('<div class="spacer"></div>')
        else:
            text = format_inline(raw)
            html_content.append(f'<p>{text}</p>')

    if in_table:
        t_html = ['<table>']
        for r_type, cells in table_rows:
            tag = 'th' if r_type == 'header' else 'td'
            row_str = '<tr>' + ''.join(f'<{tag}>{c}</{tag}>' for c in cells) + '</tr>'
            t_html.append(row_str)
        t_html.append('</table>')
        html_content.append('\n'.join(t_html))

    body = '\n'.join(html_content)

    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>{title}</title>
<style>
  @page {{
    size: A4;
    margin: 20mm 15mm 20mm 15mm;
    @bottom-right {{
      content: counter(page);
    }}
  }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    color: #0F172A;
    background: #FFFFFF;
    line-height: 1.6;
    font-size: 13px;
    margin: 0;
    padding: 0;
  }}
  .header-box {{
    background: linear-gradient(135deg, #0F172A 0%, #1E293B 100%);
    color: #FFFFFF;
    padding: 24px 28px;
    border-radius: 10px;
    margin-bottom: 24px;
    border-left: 6px solid #10B981;
  }}
  .header-box h1 {{
    color: #FFFFFF;
    margin: 0 0 6px 0;
    font-size: 20px;
    font-weight: 800;
    letter-spacing: -0.3px;
  }}
  .header-box .sub {{
    color: #94A3B8;
    font-size: 12px;
    font-weight: 500;
  }}
  h1 {{
    color: #0F172A;
    font-size: 18px;
    font-weight: 800;
    margin-top: 24px;
    margin-bottom: 12px;
    border-bottom: 2px solid #E2E8F0;
    padding-bottom: 6px;
  }}
  h2 {{
    color: #1E293B;
    font-size: 15px;
    font-weight: 700;
    margin-top: 20px;
    margin-bottom: 8px;
    border-bottom: 1px solid #F1F5F9;
    padding-bottom: 4px;
  }}
  h3 {{
    color: #334155;
    font-size: 13.5px;
    font-weight: 700;
    margin-top: 14px;
    margin-bottom: 6px;
  }}
  h4 {{
    color: #475569;
    font-size: 13px;
    font-weight: 600;
    margin-top: 10px;
    margin-bottom: 4px;
  }}
  p {{
    margin: 6px 0;
  }}
  ul, ol {{
    margin: 6px 0 12px 20px;
    padding: 0;
  }}
  li {{
    margin-bottom: 4px;
  }}
  hr {{
    border: none;
    border-top: 1px solid #E2E8F0;
    margin: 18px 0;
  }}
  .spacer {{
    height: 6px;
  }}
  table {{
    width: 100%;
    border-collapse: collapse;
    margin: 14px 0;
    font-size: 12px;
    background: #FFFFFF;
    border: 1px solid #CBD5E1;
    border-radius: 6px;
    overflow: hidden;
  }}
  th {{
    background: #F1F5F9;
    color: #0F172A;
    font-weight: 700;
    text-align: left;
    padding: 8px 12px;
    border: 1px solid #CBD5E1;
  }}
  td {{
    padding: 7px 12px;
    border: 1px solid #E2E8F0;
    color: #334155;
  }}
  tr:nth-child(even) td {{
    background: #F8FAFC;
  }}
  pre {{
    background: #0F172A;
    color: #F8FAFC;
    padding: 14px 16px;
    border-radius: 8px;
    font-family: "Cascadia Code", "Fira Code", Consolas, Courier, monospace;
    font-size: 11px;
    line-height: 1.5;
    overflow-x: auto;
    margin: 12px 0;
  }}
  code {{
    font-family: "Cascadia Code", "Fira Code", Consolas, Courier, monospace;
    background: #F1F5F9;
    color: #0F172A;
    padding: 2px 5px;
    border-radius: 4px;
    font-size: 11.5px;
  }}
  pre code {{
    background: transparent;
    color: inherit;
    padding: 0;
  }}
  .badge-pass {{
    background: #DCFCE7;
    color: #15803D;
    font-weight: 700;
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 11px;
    display: inline-block;
  }}
  .badge-warn {{
    background: #FEF3C7;
    color: #B45309;
    font-weight: 700;
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 11px;
    display: inline-block;
  }}
</style>
</head>
<body>
<div class="header-box">
  <h1>{title}</h1>
  <div class="sub">{subtitle}</div>
</div>
{body}
</body>
</html>
"""
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(full_html)

def format_inline(text):
    import re
    # Bold
    text = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', text)
    # Inline code
    text = re.sub(r'`(.*?)`', r'<code>\1</code>', text)
    # Pass badge
    text = text.replace('**PASSED**', '<span class="badge-pass">PASSED</span>')
    text = text.replace('PASSED', '<span class="badge-pass">PASSED</span>')
    return text

def html_to_pdf(html_path, pdf_path):
    browsers = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    ]
    browser = None
    for b in browsers:
        if os.path.exists(b):
            browser = b
            break

    if not browser:
        print("No browser found for PDF generation.")
        return False

    abs_html = os.path.abspath(html_path)
    abs_pdf = os.path.abspath(pdf_path)
    url = f"file:///{abs_html.replace(os.sep, '/')}"

    cmd = [
        browser,
        "--headless=new",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--print-to-pdf={abs_pdf}",
        url
    ]
    print(f"Generating PDF: {abs_pdf}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if os.path.exists(abs_pdf) and os.path.getsize(abs_pdf) > 0:
        print(f"Successfully created: {abs_pdf} ({os.path.getsize(abs_pdf)} bytes)")
        return True
    else:
        print(f"Error creating PDF: {result.stderr}")
        return False

if __name__ == '__main__':
    base_dir = r"d:\notenra"
    
    # 1. Audit Report
    audit_md = os.path.join(base_dir, "AUDIT_REPORT.md")
    audit_html = os.path.join(base_dir, "AUDIT_REPORT.html")
    audit_pdf = os.path.join(base_dir, "NOTENRA_SECURITY_COMPLIANCE_AUDIT_REPORT.pdf")
    convert_md_to_html(
        audit_md, 
        audit_html, 
        "Notenra Clinical AI — Compliance, Security & Architecture Audit", 
        "HIPAA (45 CFR § 164), HITECH & NIST SP 800-53 Technical Safeguards Audit | Version 2.4.0-PROD"
    )
    html_to_pdf(audit_html, audit_pdf)

    # 2. Developer Guide
    dev_md = os.path.join(base_dir, "DEVELOPER_GUIDE.md")
    dev_html = os.path.join(base_dir, "DEVELOPER_GUIDE.html")
    dev_pdf = os.path.join(base_dir, "NOTENRA_DEVELOPER_ARCHITECTURE_GUIDE.pdf")
    convert_md_to_html(
        dev_md, 
        dev_html, 
        "Notenra Clinical AI — Developer Architecture & Onboarding Guide", 
        "Core Subsystems, Offline Synchronization, AudioVault, AI SOAP & Coding Pipeline | Version 2.4.0-PROD"
    )
    html_to_pdf(dev_html, dev_pdf)
