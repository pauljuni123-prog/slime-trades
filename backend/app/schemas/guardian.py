from pydantic import BaseModel
from datetime import datetime
from typing import Dict, Any

class GuardianRuleCreate(BaseModel):
    rule_type: str
    settings: Dict[str, Any] = {}

class GuardianRuleResponse(BaseModel):
    id: str
    rule_type: str
    is_active: bool
    settings: Dict[str, Any]
    created_at: datetime
    class Config:
        from_attributes = True

class PositionSizeRequest(BaseModel):
    balance: float
    risk_percent: float
    stop_loss_pips: float
    pair: str = "EUR/USD"

class PositionSizeResponse(BaseModel):
    risk_amount: float
    lot_size: float
    units: int

class RiskOfRuinRequest(BaseModel):
    balance: float
    risk_percent: float
    win_rate: float
    reward_risk_ratio: float

class RiskOfRuinResponse(BaseModel):
    ruin_probability: float
    max_drawdown: float
    expected_value_per_trade: float
    risk_label: str
