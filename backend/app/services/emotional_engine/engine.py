def calculate_readiness(stress, focus, confidence, sleep):
    return int((focus + confidence + sleep - stress + 300) / 6)

def get_label(score):
    if score >= 85: return "Optimal"
    if score >= 70: return "Good"
    if score >= 55: return "Caution"
    if score >= 40: return "Warning"
    return "Critical"

def get_advice(label):
    advice = {
        "Optimal": "You are in peak condition. Execute your plan with confidence.",
        "Good": "You are ready to trade. Stick to your rules and manage risk.",
        "Caution": "Take a short break. Review your plan before entering any trades.",
        "Warning": "Step away from the charts. Do not trade in this state.",
        "Critical": "Trading is NOT recommended. Rest, hydrate, and reset."
    }
    return advice.get(label, "Assess your condition before trading.")
