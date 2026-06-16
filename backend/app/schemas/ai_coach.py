from pydantic import BaseModel
from datetime import datetime
from typing import List

class ConversationCreate(BaseModel):
    personality: str = "balanced"
    title: str | None = "New Conversation"

class MessageCreate(BaseModel):
    conversation_id: str
    content: str

class MessageResponse(BaseModel):
    id: str
    role: str
    content: str
    created_at: datetime
    class Config:
        from_attributes = True

class ConversationResponse(BaseModel):
    id: str
    personality: str
    title: str
    messages: List[MessageResponse]
    created_at: datetime
    class Config:
        from_attributes = True
