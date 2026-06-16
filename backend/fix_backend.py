import os

base = os.path.dirname(os.path.abspath(__file__))

def write(path, content):
    full = os.path.join(base, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content.strip() + "\n")
    print(f"  OK: {path}")

print("Creating all backend files...")

# Core files
write("app/__init__.py", "")
write("app/config.py", """
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DATABASE_URL: str = \"sqlite:///./slimetrades.db\"
    SECRET_KEY: str = \"slime-secret-key-2026\"
    ALGORITHM: str = \"HS256\"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080

settings = Settings()
""")

write("app/database.py", """
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from app.config import settings

engine = create_engine(
    settings.DATABASE_URL,
    connect_args={\"check_same_thread\": False}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
""")

write("app/main.py", """
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base
from app.routers import auth, mind_scan, ai_coach, guardian, mt5

app = FastAPI(title=\"Slime Trades API\", version=\"0.1.0\")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[\"*\"],
    allow_credentials=True,
    allow_methods=[\"*\"],
    allow_headers=[\"*\"],
)

Base.metadata.create_all(bind=engine)

@app.get(\"/health\")
def health_check():
    return {\"status\": \"ok\"}

app.include_router(auth.router, prefix=\"/auth\", tags=[\"Auth\"])
app.include_router(mind_scan.router, prefix=\"/mind-scans\", tags=[\"Mind Scan\"])
app.include_router(ai_coach.router, prefix=\"/ai\", tags=[\"AI Coach\"])
app.include_router(guardian.router, prefix=\"/guardian\", tags=[\"Guardian\"])
app.include_router(mt5.router, prefix=\"/mt5\", tags=[\"MT5\"])
""")

# Core
write("app/core/__init__.py", "")
write("app/core/security.py", """
from datetime import datetime, timedelta
from jose import JWTError, jwt
from passlib.context import CryptContext
from app.config import settings

pwd_context = CryptContext(schemes=[\"bcrypt\"], deprecated=\"auto\")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

def create_access_token(data: dict) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode({**data, \"exp\": expire}, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

def decode_token(token: str):
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        return None
""")

write("app/core/deps.py", """
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.core.security import decode_token

security = HTTPBearer()

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
):
    payload = decode_token(credentials.credentials)
    if not payload or \"sub\" not in payload:
        raise HTTPException(status_code=401, detail=\"Invalid token\")
    user = db.query(User).filter(User.id == payload[\"sub\"]).first()
    if not user:
        raise HTTPException(status_code=401, detail=\"User not found\")
    return user
""")

# Models
write("app/models/__init__.py", "")
write("app/models/user.py", """
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime
from sqlalchemy.orm import relationship
from app.database import Base

class User(Base):
    __tablename__ = \"users\"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String(255), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    display_name = Column(String(100))
    timezone = Column(String(50), default=\"UTC\")
    currency = Column(String(10), default=\"USD\")
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    mind_scans = relationship(\"MindScan\", back_populates=\"user\")
    conversations = relationship(\"Conversation\", back_populates=\"user\")
    guardian_rules = relationship(\"GuardianRule\", back_populates=\"user\")
    mt5_accounts = relationship(\"MT5Account\", back_populates=\"user\")
""")

write("app/models/mind_scan.py", """
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from app.database import Base

class MindScan(Base):
    __tablename__ = \"mind_scans\"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey(\"users.id\"), nullable=False, index=True)
    stress = Column(Integer, nullable=False)
    focus = Column(Integer, nullable=False)
    confidence = Column(Integer, nullable=False)
    sleep = Column(Integer, nullable=False)
    readiness_score = Column(Integer, nullable=False)
    label = Column(String(50), nullable=False)
    advice = Column(String(1000), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    user = relationship(\"User\", back_populates=\"mind_scans\")
""")

write("app/models/ai_conversation.py", """
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from app.database import Base

class Conversation(Base):
    __tablename__ = \"ai_conversations\"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey(\"users.id\"), nullable=False, index=True)
    personality = Column(String(50), default=\"balanced\", nullable=False)
    title = Column(String(255), default=\"New Conversation\", nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    messages = relationship(\"Message\", back_populates=\"conversation\", cascade=\"all, delete-orphan\", order_by=\"Message.created_at\")
    user = relationship(\"User\", back_populates=\"conversations\")

class Message(Base):
    __tablename__ = \"ai_messages\"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    conversation_id = Column(String(36), ForeignKey(\"ai_conversations.id\"), nullable=False, index=True)
    role = Column(String(20), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    conversation = relationship(\"Conversation\", back_populates=\"messages\")
""")

write("app/models/guardian_rule.py", """
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship
from app.database import Base

class GuardianRule(Base):
    __tablename__ = \"guardian_rules\"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey(\"users.id\"), nullable=False, index=True)
    rule_type = Column(String(50), nullable=False)
    is_active = Column(Boolean, default=True)
    settings = Column(JSON, default=dict)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    user = relationship(\"User\", back_populates=\"guardian_rules\")
""")

write("app/models/mt5_account.py", """
import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from app.database import Base

class MT5Account(Base):
    __tablename__ = \"mt5_accounts\"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey(\"users.id\"), nullable=False, index=True)
    broker = Column(String(100))
    server = Column(String(100))
    account_number = Column(String(50))
    password_hash = Column(String(255))
    is_connected = Column(Boolean, default=False)
    last_sync = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    user = relationship(\"User\", back_populates=\"mt5_accounts\")
    trades = relationship(\"MT5Trade\", back_populates=\"account\", cascade=\"all, delete-orphan\")

class MT5Trade(Base):
    __tablename__ = \"mt5_trades\"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    mt5_account_id = Column(String(36), ForeignKey(\"mt5_accounts.id\"), nullable=False, index=True)
    ticket = Column(String(50))
    pair = Column(String(10))
    direction = Column(String(10))
    lots = Column(String(20))
    open_price = Column(String(20))
    close_price = Column(String(20))
    pnl = Column(String(20))
    status = Column(String(20))
    synced_at = Column(DateTime, default=datetime.utcnow)
    account = relationship(\"MT5Account\", back_populates=\"trades\")
""")

# Schemas
write("app/schemas/__init__.py", "")
write("app/schemas/auth.py", """
from pydantic import BaseModel, EmailStr
from datetime import datetime

class UserCreate(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str = \"bearer\"

class UserResponse(BaseModel):
    id: str
    email: str
    display_name: str | None
    is_active: bool
    created_at: datetime
    class Config:
        from_attributes = True
""")

write("app/schemas/mind_scan.py", """
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
""")

write("app/schemas/ai_coach.py", """
from pydantic import BaseModel
from datetime import datetime
from typing import List

class ConversationCreate(BaseModel):
    personality: str = \"balanced\"
    title: str | None = \"New Conversation\"

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
""")

write("app/schemas/guardian.py", """
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
    pair: str = \"EUR/USD\"

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
""")

write("app/schemas/mt5.py", """
from pydantic import BaseModel
from datetime import datetime
from typing import List

class MT5AccountCreate(BaseModel):
    broker: str
    server: str
    account_number: str
    password: str

class MT5AccountResponse(BaseModel):
    id: str
    broker: str
    server: str
    account_number: str
    is_connected: bool
    last_sync: datetime | None
    created_at: datetime
    class Config:
        from_attributes = True

class MT5TradeResponse(BaseModel):
    id: str
    ticket: str
    pair: str
    direction: str
    lots: str
    pnl: str
    status: str
    synced_at: datetime
    class Config:
        from_attributes = True

class SyncStatusResponse(BaseModel):
    is_connected: bool
    last_sync: datetime | None
    trades_today: int
    latency_ms: int
""")

# Routers
write("app/routers/__init__.py", "")
write("app/routers/auth.py", """
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.schemas.auth import UserCreate, UserLogin, Token, UserResponse
from app.core.security import hash_password, verify_password, create_access_token
import uuid

router = APIRouter()

@router.post(\"/register\", response_model=UserResponse)
def register(user_data: UserCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == user_data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail=\"Email already registered\")
    new_user = User(
        id=str(uuid.uuid4()),
        email=user_data.email,
        password_hash=hash_password(user_data.password),
        display_name=user_data.display_name
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

@router.post(\"/login\", response_model=Token)
def login(credentials: UserLogin, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == credentials.email).first()
    if not user or not verify_password(credentials.password, user.password_hash):
        raise HTTPException(status_code=401, detail=\"Invalid credentials\")
    token = create_access_token({\"sub\": user.id})
    return {\"access_token\": token, \"token_type\": \"bearer\"}
""")

write("app/routers/mind_scan.py", """
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.mind_scan import MindScan
from app.schemas.mind_scan import MindScanCreate, MindScanResponse
from app.core.deps import get_current_user
from app.services.emotional_engine.engine import calculate_readiness, get_label, get_advice
import uuid

router = APIRouter()

@router.post(\"/\", response_model=MindScanResponse)
def create_scan(scan_data: MindScanCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    readiness = calculate_readiness(scan_data.stress, scan_data.focus, scan_data.confidence, scan_data.sleep)
    label = get_label(readiness)
    advice = get_advice(label)
    new_scan = MindScan(
        id=str(uuid.uuid4()), user_id=current_user.id,
        stress=scan_data.stress, focus=scan_data.focus,
        confidence=scan_data.confidence, sleep=scan_data.sleep,
        readiness_score=readiness, label=label, advice=advice
    )
    db.add(new_scan)
    db.commit()
    db.refresh(new_scan)
    return new_scan

@router.get(\"/\", response_model=list[MindScanResponse])
def list_scans(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(MindScan).filter(MindScan.user_id == current_user.id).order_by(MindScan.created_at.desc()).all()

@router.get(\"/latest\", response_model=MindScanResponse)
def get_latest(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    scan = db.query(MindScan).filter(MindScan.user_id == current_user.id).order_by(MindScan.created_at.desc()).first()
    if not scan:
        raise HTTPException(status_code=404, detail=\"No scans found\")
    return scan
""")

write("app/routers/ai_coach.py", """
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.ai_conversation import Conversation, Message
from app.schemas.ai_coach import ConversationCreate, MessageCreate, MessageResponse, ConversationResponse
from app.core.deps import get_current_user
from app.services.ai_coach.ai_client import generate_response
import uuid

router = APIRouter()

@router.post(\"/sessions\", response_model=ConversationResponse)
def create_session(data: ConversationCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    conv = Conversation(id=str(uuid.uuid4()), user_id=current_user.id, personality=data.personality, title=data.title)
    db.add(conv)
    db.commit()
    db.refresh(conv)
    return conv

@router.post(\"/messages\", response_model=MessageResponse)
def send_message(data: MessageCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    conv = db.query(Conversation).filter(Conversation.id == data.conversation_id, Conversation.user_id == current_user.id).first()
    if not conv:
        raise HTTPException(status_code=404, detail=\"Conversation not found\")
    user_msg = Message(id=str(uuid.uuid4()), conversation_id=conv.id, role=\"user\", content=data.content)
    db.add(user_msg)
    db.commit()
    ai_content = generate_response(data.content, conv.personality)
    ai_msg = Message(id=str(uuid.uuid4()), conversation_id=conv.id, role=\"ai\", content=ai_content)
    db.add(ai_msg)
    db.commit()
    db.refresh(ai_msg)
    return ai_msg

@router.get(\"/sessions/{conversation_id}\", response_model=ConversationResponse)
def get_session(conversation_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    conv = db.query(Conversation).filter(Conversation.id == conversation_id, Conversation.user_id == current_user.id).first()
    if not conv:
        raise HTTPException(status_code=404, detail=\"Conversation not found\")
    return conv

@router.get(\"/sessions\", response_model=list[ConversationResponse])
def list_sessions(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(Conversation).filter(Conversation.user_id == current_user.id).order_by(Conversation.created_at.desc()).all()
""")

write("app/routers/guardian.py", """
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.guardian_rule import GuardianRule
from app.schemas.guardian import GuardianRuleCreate, GuardianRuleResponse, PositionSizeRequest, PositionSizeResponse, RiskOfRuinRequest, RiskOfRuinResponse
from app.core.deps import get_current_user
import uuid

router = APIRouter()

@router.get(\"/rules\", response_model=list[GuardianRuleResponse])
def list_rules(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(GuardianRule).filter(GuardianRule.user_id == current_user.id).all()

@router.post(\"/rules\", response_model=GuardianRuleResponse)
def create_rule(data: GuardianRuleCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    rule = GuardianRule(id=str(uuid.uuid4()), user_id=current_user.id, rule_type=data.rule_type, settings=data.settings)
    db.add(rule)
    db.commit()
    db.refresh(rule)
    return rule

@router.put(\"/rules/{rule_id}\", response_model=GuardianRuleResponse)
def toggle_rule(rule_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    rule = db.query(GuardianRule).filter(GuardianRule.id == rule_id, GuardianRule.user_id == current_user.id).first()
    if not rule:
        raise HTTPException(status_code=404, detail=\"Rule not found\")
    rule.is_active = not rule.is_active
    db.commit()
    db.refresh(rule)
    return rule

@router.post(\"/position-size\", response_model=PositionSizeResponse)
def position_size(data: PositionSizeRequest):
    risk_amount = data.balance * (data.risk_percent / 100)
    pip_values = {\"EUR/USD\": 0.0001, \"GBP/USD\": 0.0001, \"USD/JPY\": 0.01, \"XAU/USD\": 0.01}
    pip_value = pip_values.get(data.pair, 0.0001)
    units = risk_amount / (data.stop_loss_pips * pip_value)
    lot_size = units / 100000
    return {\"risk_amount\": risk_amount, \"lot_size\": lot_size, \"units\": int(units)}

@router.post(\"/risk-of-ruin\", response_model=RiskOfRuinResponse)
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
    label = \"Safe\" if ruin_prob < 5 else \"Moderate\" if ruin_prob < 20 else \"Dangerous\"
    return {
        \"ruin_probability\": round(ruin_prob, 2),
        \"max_drawdown\": round(max_dd, 2),
        \"expected_value_per_trade\": round(ev, 2),
        \"risk_label\": label
    }
""")

write("app/routers/mt5.py", """
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.mt5_account import MT5Account, MT5Trade
from app.schemas.mt5 import MT5AccountCreate, MT5AccountResponse, MT5TradeResponse, SyncStatusResponse
from app.core.deps import get_current_user
from app.core.security import hash_password
import uuid
from datetime import datetime

router = APIRouter()

@router.post(\"/accounts\", response_model=MT5AccountResponse)
def add_account(data: MT5AccountCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    existing = db.query(MT5Account).filter(
        MT5Account.user_id == current_user.id,
        MT5Account.account_number == data.account_number
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail=\"Account already linked\")
    account = MT5Account(
        id=str(uuid.uuid4()), user_id=current_user.id,
        broker=data.broker, server=data.server,
        account_number=data.account_number,
        password_hash=hash_password(data.password),
        is_connected=False
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account

@router.get(\"/accounts\", response_model=list[MT5AccountResponse])
def list_accounts(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(MT5Account).filter(MT5Account.user_id == current_user.id).all()

@router.delete(\"/accounts/{account_id}\")
def remove_account(account_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    account = db.query(MT5Account).filter(MT5Account.id == account_id, MT5Account.user_id == current_user.id).first()
    if not account:
        raise HTTPException(status_code=404, detail=\"Account not found\")
    db.delete(account)
    db.commit()
    return {\"message\": \"Account removed\"}

@router.get(\"/accounts/{account_id}/trades\", response_model=list[MT5TradeResponse])
def get_trades(account_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    account = db.query(MT5Account).filter(MT5Account.id == account_id, MT5Account.user_id == current_user.id).first()
    if not account:
        raise HTTPException(status_code=404, detail=\"Account not found\")
    return db.query(MT5Trade).filter(MT5Trade.mt5_account_id == account_id).order_by(MT5Trade.synced_at.desc()).all()

@router.get(\"/accounts/{account_id}/status\", response_model=SyncStatusResponse)
def get_status(account_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    account = db.query(MT5Account).filter(MT5Account.id == account_id, MT5Account.user_id == current_user.id).first()
    if not account:
        raise HTTPException(status_code=404, detail=\"Account not found\")
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    trades_today = db.query(MT5Trade).filter(
        MT5Trade.mt5_account_id == account_id,
        MT5Trade.synced_at >= today
    ).count()
    return {
        \"is_connected\": account.is_connected,
        \"last_sync\": account.last_sync,
        \"trades_today\": trades_today,
        \"latency_ms\": 0
    }
""")

# Services
write("app/services/__init__.py", "")
write("app/services/emotional_engine/__init__.py", "")
write("app/services/emotional_engine/engine.py", """
def calculate_readiness(stress, focus, confidence, sleep):
    return int((focus + confidence + sleep - stress + 300) / 6)

def get_label(score):
    if score >= 85: return \"Optimal\"
    if score >= 70: return \"Good\"
    if score >= 55: return \"Caution\"
    if score >= 40: return \"Warning\"
    return \"Critical\"

def get_advice(label):
    advice = {
        \"Optimal\": \"You are in peak condition. Execute your plan with confidence.\",
        \"Good\": \"You are ready to trade. Stick to your rules and manage risk.\",
        \"Caution\": \"Take a short break. Review your plan before entering any trades.\",
        \"Warning\": \"Step away from the charts. Do not trade in this state.\",
        \"Critical\": \"Trading is NOT recommended. Rest, hydrate, and reset.\"
    }
    return advice.get(label, \"Assess your condition before trading.\")
""")

write("app/services/ai_coach/__init__.py", "")
write("app/services/ai_coach/ai_client.py", """
def generate_response(user_message: str, personality: str = \"balanced\") -> str:
    personalities = {
        \"aggressive\": \"Go big or go home. But only if the setup is A+.\",
        \"conservative\": \"Preserve capital first. Small wins compound.\",
        \"balanced\": \"Find the middle path. Good risk/reward, tight stops.\",
        \"mentor\": \"Let me walk you through this step by step...\"
    }
    tone = personalities.get(personality, personalities[\"balanced\"])
    return f\"[{personality.upper()}] {tone} | You asked: '{user_message}'. Here is my analysis: Consider market structure, volume, and your emotional state before acting.\"
""")

write("app/services/guardian/__init__.py", "")
write("app/services/guardian/rules_engine.py", """
def check_trade_against_rules(trade, rules):
    violations = []
    for rule in rules:
        if not rule.is_active:
            continue
        if rule.rule_type == \"max_position_size\":
            max_size = rule.settings.get(\"max_lots\", 1.0)
            if trade.get(\"lots\", 0) > max_size:
                violations.append(f\"Position size {trade['lots']} exceeds max {max_size}\")
        if rule.rule_type == \"trading_hours\":
            import datetime
            now = datetime.datetime.utcnow().hour
            allowed = rule.settings.get(\"hours\", [9, 10, 11, 12, 13, 14, 15, 16])
            if now not in allowed:
                violations.append(f\"Trading outside allowed hours: {allowed}\")
        if rule.rule_type == \"max_daily_loss\":
            daily_loss = rule.settings.get(\"limit\", 100)
            if trade.get(\"pnl\", 0) < -daily_loss:
                violations.append(f\"Daily loss limit of {daily_loss} exceeded\")
    return violations
""")

print("\n========================================")
print("ALL FILES CREATED SUCCESSFULLY!")
print("========================================")
print("\nNext: python fix_backend.py")
