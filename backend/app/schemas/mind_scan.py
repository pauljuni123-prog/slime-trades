from pydantic import BaseModel, Field
from datetime import datetime

class MindScanCreate(BaseModel):
    stress: int = Field(ge=0, le=100)
    focus: int = Field(ge=0, le=100)
    confidence: int = Field(ge=0, le=100)
    sleep: int = Field(ge=0, le=100)

class MindScanResponse(BaseModel):
    id: str
    user_id: str
    stress: int
    focus: int
    confidence: int
    sleep: int
    readiness_score: int
    label: str
    advice: str
    created_at: datetime
    class Config:
        from_attributes = True
