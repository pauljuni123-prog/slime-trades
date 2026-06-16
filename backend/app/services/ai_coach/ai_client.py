def generate_response(user_message: str, personality: str = "balanced") -> str:
    personalities = {
        "aggressive": "Go big or go home. But only if the setup is A+.",
        "conservative": "Preserve capital first. Small wins compound.",
        "balanced": "Find the middle path. Good risk/reward, tight stops.",
        "mentor": "Let me walk you through this step by step..."
    }
    tone = personalities.get(personality, personalities["balanced"])
    return f"[{personality.upper()}] {tone} | You asked: '{user_message}'. Here is my analysis: Consider market structure, volume, and your emotional state before acting."
