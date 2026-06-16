import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from app.database import Base

class MT5Account(Base):
    __tablename__ = "mt5_accounts"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    broker = Column(String(100))
    server = Column(String(100))
    account_number = Column(String(50))
    password_hash = Column(String(255))
    is_connected = Column(Boolean, default=False)
    last_sync = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    user = relationship("User", back_populates="mt5_accounts")
    trades = relationship("MT5Trade", back_populates="account", cascade="all, delete-orphan")

class MT5Trade(Base):
    __tablename__ = "mt5_trades"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    mt5_account_id = Column(String(36), ForeignKey("mt5_accounts.id"), nullable=False, index=True)
    ticket = Column(String(50))
    pair = Column(String(10))
    direction = Column(String(10))
    lots = Column(String(20))
    open_price = Column(String(20))
    close_price = Column(String(20))
    pnl = Column(String(20))
    status = Column(String(20))
    synced_at = Column(DateTime, default=datetime.utcnow)
    account = relationship("MT5Account", back_populates="trades")
