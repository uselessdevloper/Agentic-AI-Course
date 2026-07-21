import os
import anthropic
from anthropic import AnthropicBedrock
from dotenv import load_dotenv

# 1. Load environment variables from .env
load_dotenv()

# 2. System prompt starter setup
SYSTEM = """
You are a Senior BSA at {{client}}.
Analyse {{system}} {{domain}} reqs.
Return ONLY valid JSON. No preamble.
"""

def get_client_and_model():
    """
    Resolves client and model for either direct Anthropic API or Amazon Bedrock.
    """
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

def run_quickstart():
    print("==========================================")
    print(" Quick-Start: Claude API Runner           ")
    print("==========================================")
    
    system_prompt = (
        SYSTEM.replace("{{client}}", "AIG Insurance")
              .replace("{{system}}", "SAP S/4HANA")
              .replace("{{domain}}", "P2P")
    )

    client, model_name = get_client_and_model()

    if not client:
        print("ANTHROPIC_API_KEY / AWS Bedrock credentials not configured in .env.")
        print("Displaying simulated response for Quick-Start demo:\n")
        simulated_response = '''[
  {"id": "FR-001", "title": "Leave Entitlement Tracking", "description": "Track annual, sick, and carry-forward balances.", "priority": "High"},
  {"id": "FR-002", "title": "Leave Request Submission", "description": "Employees can submit leave requests with date pickers.", "priority": "High"},
  {"id": "FR-003", "title": "Manager Approval Workflow", "description": "Managers receive notifications to approve or reject leave requests.", "priority": "High"},
  {"id": "FR-004", "title": "Carry-Forward Validation Rules", "description": "Validate max carry-forward limit at fiscal year end.", "priority": "Medium"},
  {"id": "FR-005", "title": "Leave Audit Logging", "description": "Maintain immutable log of all leave adjustments.", "priority": "Medium"}
]'''
        print(simulated_response)
        return simulated_response

    try:
        response = client.messages.create(
            model=model_name,
            max_tokens=2000,
            system=system_prompt,
            messages=[{
                "role": "user",
                "content": "Generate 5 user stories for a leave management system."
            }]
        )
        output = response.content[0].text
        print("API Response from Claude:")
        print(output)
        return output
    except Exception as e:
        print(f" API Call failed: {e}")
        return None

if __name__ == "__main__":
    run_quickstart()
