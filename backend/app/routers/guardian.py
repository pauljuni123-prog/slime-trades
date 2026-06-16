from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.guardian_rule import GuardianRule
from app.schemas.guardian import GuardianRuleCreate, GuardianRuleResponse, PositionSizeRequest, PositionSizeResponse, RiskOfRuinRequest, RiskOfRuinResponse
from app.core.deps import get_current_user
import uuid

router = APIRouter()

@router.get("/rules", response_model=list[GuardianRuleResponse])
def list_rules(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(GuardianRule).filter(GuardianRule.user_id == current_user.id).all()

@router.post("/rules", response_model=GuardianRuleResponse)
def create_rule(data: GuardianRuleCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    rule = GuardianRule(id=str(uuid.uuid4()), user_id=current_user.id, rule_type=data.rule_type, settings=data.settings)
    db.add(rule)
    db.commit()
    db.refresh(rule)
    return rule

@router.put("/rules/{rule_id}", response_model=GuardianRuleResponse)
def toggle_rule(rule_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    rule = db.query(GuardianRule).filter(GuardianRule.id == rule_id, GuardianRule.user_id == current_user.id).first()
    if not rule:
        raise HTTPException(status_code=404, detail="Rule not found")
    rule.is_active = not rule.is_active
    db.commit()
    db.refresh(rule)
    return rule

@router.post("/position-size", response_model=PositionSizeResponse)
def position_size(data: PositionSizeRequest):
    risk_amount = data.balance * (data.risk_percent / 100)
    pip_values = {"EUR/USD": 0.0001, "GBP/USD": 0.0001, "USD/JPY": 0.01, "XAU/USD": 0.01}
    pip_value = pip_values.get(data.pair, 0.0001)
    units = risk_amount / (data.stop_loss_pips * pip_value)
    lot_size = units / 100000
    return {"risk_amount": risk_amount, "lot_size": lot_size, "units": int(units)}

@router.post("/risk-of-ruin", response_model=RiskOfRuinResponse)
def risk_of_ruin(data: RiskOfRuinRequest):
    win_rate = data.win_rate / 100
    edge = (win_rate * data.reward_risk_ratio) - (1 - win_rate)
    risk_unit = data.balance * (data.risk_percent / 100)
    if edge <= 0:
        ruin_prob = 100.0
        max_dd = 100.0
    else:
        bankroll_units = data.balance / risk_unit
        q = (1 - edge) / (1 + edge)
        if q <= 0:
            ruin_prob = 0.0
        else:
            ruin_prob = (q ** bankroll_units) * 100
        max_dd = risk_unit * 10
    ev = (win_rate * data.reward_risk_ratio * risk_unit) - ((1 - win_rate) * risk_unit)
    label = "Safe" if ruin_prob < 5 else "Moderate" if ruin_prob < 20 else "Dangerous"
    return {
        "ruin_probability": round(ruin_prob, 2),
        "max_drawdown": round(max_dd, 2),
        "expected_value_per_trade": round(ev, 2),
        "risk_label": label
    }
