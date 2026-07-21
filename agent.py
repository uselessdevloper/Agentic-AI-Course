import argparse
import sys
from agent_runner import run_quickstart
from lab1_bsa_agent import run_lab1
from lab2_prompt_chain import run_lab2

def main():
    parser = argparse.ArgumentParser(description="Prompt Engineering Labs Runner")
    parser.add_argument("--lab", type=int, choices=[1, 2], help="Lab number to run (1 or 2)")
    parser.add_argument("--quickstart", action="store_true", help="Run quickstart agent runner")
    parser.add_argument("--all", action="store_true", help="Run all labs and quickstart")

    args = parser.parse_args()

    if args.quickstart:
        run_quickstart()
    elif args.lab == 1:
        run_lab1()
    elif args.lab == 2:
        run_lab2()
    elif args.all or len(sys.argv) == 1:
        print(" Running All Prompt Engineering Labs & Quick-Start...\n")
        run_quickstart()
        print("\n\n")
        run_lab1()
        print("\n\n")
        run_lab2()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
