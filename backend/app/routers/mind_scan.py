from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.mind_scan import MindScan
from app.schemas.mind_scan import MindScanCreate, MindScanResponse
from app.core.deps import get_current_user
from app.services.emotional_engine.engine import calculate_readiness, get_label, get_advice
import uuid

router = APIRouter()

@router.post("/", response_model=MindScanResponse)
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

@router.get("/", response_model=list[MindScanResponse])
def list_scans(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(MindScan).filter(MindScan.user_id == current_user.id).order_by(MindScan.created_at.desc()).all()

@router.get("/latest", response_model=MindScanResponse)
def get_latest(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    scan = db.query(MindScan).filter(MindScan.user_id == current_user.id).order_by(MindScan.created_at.desc()).first()
    if not scan:
        raise HTTPException(status_code=404, detail="No scans found")
    return scan
