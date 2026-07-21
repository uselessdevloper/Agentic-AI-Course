import os
import json
import anthropic
from anthropic import AnthropicBedrock
from dotenv import load_dotenv

load_dotenv()

# Step 1 Prompts
STEP1_SYSTEM = """You are a BSA. Analyse the feature below. Extract structured requirements. Return ONLY a JSON array: [{id, title, description, priority}]. NEVER add preamble."""
STEP1_USER_TEMPLATE = """Feature: {{raw_feature}}"""

# Step 2 Prompts
STEP2_SYSTEM = """You are a Product Owner. Convert the requirements below into user stories. Return ONLY a JSON array: [{id, as_a, i_want, so_that, priority}]. NEVER add preamble."""
STEP2_USER_TEMPLATE = """Requirements: {{step1_output}}"""

# Step 3 Prompts
STEP3_SYSTEM = """You are a QA Lead. Generate BDD test cases from the user stories below. Return ONLY a JSON array: [{id, story_id, scenario, given, when, then, expected_result}]. Cover happy and sad paths."""
STEP3_USER_TEMPLATE = """User Stories: {{step2_output}}"""

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

def call_llm(system_prompt: str, user_prompt: str) -> str:
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
        return response.content[0].text.strip()
    except Exception as e:
        print(f"API call error: {e}")
        return None

def get_simulated_step1_output() -> str:
    return json.dumps([
        {
            "id": "FR-001",
            "title": "Annual Leave Balance Tracking",
            "description": "System shall maintain and update annual leave balances per student.",
            "priority": "High"
        },
        {
            "id": "FR-002",
            "title": "Sick Leave Entitlement Management",
            "description": "System shall record sick leave usage against annual sick leave quotas.",
            "priority": "High"
        },
        {
            "id": "FR-003",
            "title": "Carry-Forward Balance Calculation",
            "description": "System shall calculate eligible unused leave carry-forward balances at year end.",
            "priority": "Medium"
        }
    ], indent=2)

def get_simulated_step2_output() -> str:
    return json.dumps([
        {
            "id": "US-001",
            "as_a": "Student",
            "i_want": "to view my current annual and sick leave balances",
            "so_that": "I can plan my absences accurately",
            "priority": "High"
        },
        {
            "id": "US-002",
            "as_a": "Student",
            "i_want": "unused leave to roll over into my carry-forward balance",
            "so_that": "I don't lose eligible leave at year end",
            "priority": "Medium"
        }
    ], indent=2)

def get_simulated_step3_output() -> str:
    return json.dumps([
        {
            "id": "TC-001",
            "story_id": "US-001",
            "scenario": "Successful leave balance lookup (Happy Path)",
            "given": "Student is authenticated in the portal",
            "when": "Student navigates to Leave Balance dashboard",
            "then": "Display current annual, sick, and carry-forward balances",
            "expected_result": "Balances match record accurately in database"
        },
        {
            "id": "TC-002",
            "story_id": "US-002",
            "scenario": "Exceeding carry-forward cap validation (Sad Path)",
            "given": "Student has 15 unused annual leave days and max carry-forward limit is 10 days",
            "when": "Fiscal year rollover job executes",
            "then": "Carry-forward balance is capped at 10 days and remaining 5 days expire",
            "expected_result": "System logs carry-forward cap event and notifies student"
        }
    ], indent=2)

def run_lab2():
    print(" LAB 2: 3-Step Prompt Chain (Requirement -> User Story -> Test Cases)    ")

    raw_feature = "Build a student leave management system that tracks annual leave, sick leave, and carry-forward balances."
    print(f"📥 Input Feature: '{raw_feature}'\n")

    # STEP 1: Requirement Analysis
    print(" STEP 1: Requirement Analysis Prompt (BSA Agent)")
    user_prompt_1 = STEP1_USER_TEMPLATE.replace("{{raw_feature}}", raw_feature)
    step1_output = call_llm(STEP1_SYSTEM, user_prompt_1)
    if not step1_output:
        print("Using simulated Step 1 output:")
        step1_output = get_simulated_step1_output()
    print(step1_output)
    print()

    # STEP 2: User Story Generation
    print(" STEP 2: User Story Generation Prompt (Product Owner Agent)")
    # Direct chaining rule: copy step1_output directly into {{step1_output}} variable
    user_prompt_2 = STEP2_USER_TEMPLATE.replace("{{step1_output}}", step1_output)
    step2_output = call_llm(STEP2_SYSTEM, user_prompt_2)
    if not step2_output:
        print("Using simulated Step 2 output:")
        step2_output = get_simulated_step2_output()
    print(step2_output)
    print()

    # STEP 3: Test Case Generation
    print(" STEP 3: Test Case Generation Prompt (QA Lead Agent)")
    # Direct chaining rule: copy step2_output directly into {{step2_output}} variable
    user_prompt_3 = STEP3_USER_TEMPLATE.replace("{{step2_output}}", step2_output)
    step3_output = call_llm(STEP3_SYSTEM, user_prompt_3)
    if not step3_output:
        print("Using simulated Step 3 output:")
        step3_output = get_simulated_step3_output()
    print(step3_output)
    print()

    print(" Prompt Chain Completed Successfully!")
    print(" Chain Pipeline: Feature -> [Step 1 JSON] -> [Step 2 JSON] -> [Step 3 BDD]")

if __name__ == "__main__":
    run_lab2()
