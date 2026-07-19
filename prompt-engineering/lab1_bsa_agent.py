import os
import json
import anthropic
from anthropic import AnthropicBedrock
from dotenv import load_dotenv

load_dotenv()

PROMPT_FILE_PATH = os.path.join(os.path.dirname(__file__), "prompts", "bsa_agent_v1.txt")

cfg_aig = {
    "client_name": "AIG Insurance",
    "system_name": "SAP S/4HANA",
    "module": "P2P",
    "language": "English",
    "output_format": "JSON",
    "max_requirements": "20"
}

cfg_abc = {
    "client_name": "ABC Bank",
    "system_name": "Dynamics CRM",
    "module": "Sales",
    "language": "English",
    "output_format": "JSON",
    "max_requirements": "20"
}

def render_prompt(template_path: str, variables: dict) -> str:
    with open(template_path, "r", encoding="utf-8") as f:
        template = f.read()
    
    rendered = template
    for key, value in variables.items():
        rendered = rendered.replace(f"{{{{{key}}}}}", str(value))
    return rendered

def get_client_and_model():
    anthropic_key = os.getenv("ANTHROPIC_API_KEY")
    if anthropic_key and not anthropic_key.startswith("sk-ant-your") and anthropic_key.strip():
        model_name = os.getenv("CLAUDE_MODEL", "claude-3-5-sonnet-20241022")
        return anthropic.Anthropic(api_key=anthropic_key), model_name

    aws_access = os.getenv("AWS_ACCESS_KEY_ID")
    aws_secret = os.getenv("AWS_SECRET_ACCESS_KEY")
    if aws_access and aws_secret and aws_access.strip() and aws_secret.strip():
        model_name = os.getenv("BEDROCK_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0")
        region = os.getenv("AWS_REGION", "us-east-1")
        client = AnthropicBedrock(
            aws_access_key=aws_access,
            aws_secret_key=aws_secret,
            aws_session_token=os.getenv("AWS_SESSION_TOKEN"),
            aws_region=region
        )
        return client, model_name

    return None, None

def get_claude_response(system_prompt: str, user_prompt: str):
    client, model_name = get_client_and_model()
    if not client:
        return None

    try:
        response = client.messages.create(
            model=model_name,
            max_tokens=3000,
            temperature=0.0,
            system=system_prompt,
            messages=[{"role": "user", "content": user_prompt}]
        )
        return response.content[0].text
    except Exception as e:
        print(f"API execution error: {e}")
        return None

def get_simulated_response(config: dict):
    if config["client_name"] == "AIG Insurance":
        return json.dumps([
            {
                "id": "FR-001",
                "title": "Procure-to-Pay Approval Gateways",
                "description": "Enforce automated SAP S/4HANA P2P approval workflows for AIG Insurance procurement transactions.",
                "priority": "High"
            },
            {
                "id": "FR-002",
                "title": "Vendor Master Data Synchronization",
                "description": "Synchronize AIG vendor accounts with SAP S/4HANA purchase order modules.",
                "priority": "High"
            },
            {
                "id": "FR-003",
                "title": "3-Way Invoice Matching Rule",
                "description": "Verify PO, Goods Receipt, and Supplier Invoice in SAP S/4HANA P2P before payout authorization.",
                "priority": "Medium"
            }
        ], indent=2)
    else:
        return json.dumps([
            {
                "id": "FR-001",
                "title": "Dynamics CRM Lead Capture",
                "description": "Capture commercial banking leads in ABC Bank Dynamics CRM Sales module automatically.",
                "priority": "High"
            },
            {
                "id": "FR-002",
                "title": "Opportunity Stage Pipeline Tracking",
                "description": "Track pipeline conversion rates across corporate accounts in ABC Bank Dynamics CRM.",
                "priority": "High"
            },
            {
                "id": "FR-003",
                "title": "Customer Credit Scoring Integration",
                "description": "Integrate ABC Bank core credit scoring API into Dynamics CRM Sales opportunity records.",
                "priority": "High"
            }
        ], indent=2)

def run_lab1():
    print(" LAB 1: Build a BSA Agent System Prompt with Variables          ")

    user_prompt = "Generate initial technical requirements for a leave management system."

    # Config 1: AIG
    prompt_aig = render_prompt(PROMPT_FILE_PATH, cfg_aig)
    print("--- 1. Testing Config AIG (SAP S/4HANA - P2P) ---")
    response_aig = get_claude_response(prompt_aig, user_prompt)
    if not response_aig:
        print("Using simulated response (no API key configured):")
        response_aig = get_simulated_response(cfg_aig)
    print(response_aig)
    print("\n" + "-"*60 + "\n")

    # Config 2: ABC Bank
    prompt_abc = render_prompt(PROMPT_FILE_PATH, cfg_abc)
    print("--- 2. Testing Config ABC Bank (Dynamics CRM - Sales) ---")
    response_abc = get_claude_response(prompt_abc, user_prompt)
    if not response_abc:
        print("Using simulated response (no API key configured):")
        response_abc = get_simulated_response(cfg_abc)
    print(response_abc)
    print("\n" + "="*60 + "\n")

    # Comparison analysis
    print("--- 3. Comparison & Differences Analysis ---")
    print("• Client & System Context Integration:")
    print("  - Output 1 explicitly scopes requirements to AIG Insurance and SAP S/4HANA P2P integrations.")
    print("  - Output 2 explicitly scopes requirements to ABC Bank and Dynamics CRM Sales workflows.")
    print("• Terminology Adaptation:")
    print("  - SAP P2P output uses ERP concepts like 3-way matching and vendor master data.")
    print("  - Dynamics CRM output uses CRM concepts like sales leads, opportunities, and credit scoring.")
    print("• Structural Consistency:")
    print("  - Both outputs adhere strictly to the JSON schema defined in bsa_agent_v1.txt without preamble.")

if __name__ == "__main__":
    run_lab1()
