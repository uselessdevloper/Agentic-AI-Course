How can I download  ollama? 



Step 1 Check system settings if it’s compatible or supported :  system_profiler SPHardwareDataType

Step 2  Check if Home brew is installed or not : brew --version

Step 3 Install ollama : brew install ollama

Step 4 verify id llama is installed or not : ollama --version

Step 5 Start Llama : ollama serve

Step 6 :  Download first model best one is Qwen3 8B according to my machine considering compatibility and all aspects ( approx 5-5.5 gb) : ollama pull qwen3:8b 

Step. 7 :  run the ollama model : ollama run qwen3:8b


If you want to use your locally run model that is ollama in your code then : 
1. First install open ai model through ollama:  pip install ollama openai
2. Use it like: 

from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:11434/v1",
    api_key="ollama"
)

response = client.chat.completions.create(
    model="qwen3:8b",
    messages=[
        {"role": "user", "content": "Write a FastAPI CRUD API"}
    ]
)

print(response.choices[0].message.content)

3. Run the file : python3 model.py
