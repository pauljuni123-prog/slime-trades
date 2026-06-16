from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.ai_conversation import Conversation, Message
from app.schemas.ai_coach import ConversationCreate, MessageCreate, MessageResponse, ConversationResponse
from app.core.deps import get_current_user
from app.services.ai_coach.ai_client import generate_response
import uuid

router = APIRouter()

@router.post("/sessions", response_model=ConversationResponse)
def create_session(data: ConversationCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    conv = Conversation(id=str(uuid.uuid4()), user_id=current_user.id, personality=data.personality, title=data.title)
    db.add(conv)
    db.commit()
    db.refresh(conv)
    return conv

@router.post("/messages", response_model=MessageResponse)
def send_message(data: MessageCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    conv = db.query(Conversation).filter(Conversation.id == data.conversation_id, Conversation.user_id == current_user.id).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    user_msg = Message(id=str(uuid.uuid4()), conversation_id=conv.id, role="user", content=data.content)
    db.add(user_msg)
    db.commit()
    ai_content = generate_response(data.content, conv.personality)
    ai_msg = Message(id=str(uuid.uuid4()), conversation_id=conv.id, role="ai", content=ai_content)
    db.add(ai_msg)
    db.commit()
    db.refresh(ai_msg)
    return ai_msg

@router.get("/sessions/{conversation_id}", response_model=ConversationResponse)
def get_session(conversation_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    conv = db.query(Conversation).filter(Conversation.id == conversation_id, Conversation.user_id == current_user.id).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conv

@router.get("/sessions", response_model=list[ConversationResponse])
def list_sessions(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(Conversation).filter(Conversation.user_id == current_user.id).order_by(Conversation.created_at.desc()).all()
