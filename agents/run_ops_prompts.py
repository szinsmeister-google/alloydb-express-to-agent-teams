"""Runs Priya's two opening Summit Trail Supply prompts against AlloyDB over MCP."""

import asyncio
import os
from google.adk.runners import InMemoryRunner
from google.genai import types
from operations_agent import root_agent

os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "true")
os.environ.setdefault("GOOGLE_CLOUD_PROJECT", os.environ["PROJECT_ID"])
os.environ.setdefault("GOOGLE_CLOUD_LOCATION", "us-central1")


async def ask(runner: InMemoryRunner, session_id: str, prompt: str):
    print(f"\n{'='*72}\nPROMPT: {prompt}\n{'='*72}")
    msg = types.Content(role="user", parts=[types.Part.from_text(text=prompt)])
    async for event in runner.run_async(
        user_id="priya", session_id=session_id, new_message=msg
    ):
        if event.content and event.content.parts:
            for part in event.content.parts:
                if part.function_call:
                    print(f"[MCP Tool Call] {part.function_call.name}({part.function_call.args})")
                elif part.text:
                    print(part.text)


async def main():
    runner = InMemoryRunner(agent=root_agent, app_name="summit_trail")
    try:
        session = await runner.session_service.create_session(
            app_name="summit_trail", user_id="priya"
        )
        await ask(
            runner,
            session.id,
            "Give me this morning's read on unit fill rate by month this year, against our 95% target.",
        )
        await ask(
            runner,
            session.id,
            "Which distribution center is driving the fill-rate decline?",
        )
    finally:
        await runner.close()


if __name__ == "__main__":
    asyncio.run(main())
