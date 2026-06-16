import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from app.database import Base

class MindScan(Base):
    __tablename__ = "mind_scans"
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    stress = Column(Integer, nullable=False)
    focus = Column(Integer, nullable=False)
    confidence = Column(Integer, nullable=False)
    sleep = Column(Integer, nullable=False)
    readiness_score = Column(Integer, nullable=False)
    label = Column(String(50), nullable=False)
    advice = Column(String(1000), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    user = relationship("User", back_populates="mind_scans")
