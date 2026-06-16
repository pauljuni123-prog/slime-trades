from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.mt5_account import MT5Account, MT5Trade
from app.schemas.mt5 import MT5AccountCreate, MT5AccountResponse, MT5TradeResponse, SyncStatusResponse
from app.core.deps import get_current_user
from app.core.security import hash_password
import uuid
from datetime import datetime
from typing import Optional

router = APIRouter()

# MT5 Service
class MT5Service:
    def __init__(self):
        self._initialized = False
        try:
            import MetaTrader5 as mt5
            self.mt5 = mt5
        except ImportError:
            self.mt5 = None
    
    def is_available(self) -> bool:
        return self.mt5 is not None
    
    def initialize(self, path: Optional[str] = None) -> bool:
        if not self.mt5:
            return False
        if self._initialized:
            return True
        self._initialized = self.mt5.initialize(path)
        return self._initialized
    
    def shutdown(self):
        if self.mt5 and self._initialized:
            self.mt5.shutdown()
            self._initialized = False
    
    def login(self, login: int, password: str, server: str) -> bool:
        if not self.initialize():
            return False
        return self.mt5.login(login, password, server)
    
    def get_account_info(self) -> Optional[dict]:
        if not self.mt5:
            return None
        info = self.mt5.account_info()
        if info is None:
            return None
        return {
            "login": info.login,
            "server": info.server,
            "balance": info.balance,
            "equity": info.equity,
            "margin": info.margin,
            "free_margin": info.margin_free,
            "margin_level": info.margin_level,
            "currency": info.currency
        }
    
    def get_positions(self) -> list:
        if not self.mt5:
            return []
        positions = self.mt5.positions_get()
        if positions is None:
            return []
        return [
            {
                "ticket": pos.ticket,
                "symbol": pos.symbol,
                "type": "BUY" if pos.type == 0 else "SELL",
                "volume": pos.volume,
                "open_price": pos.price_open,
                "current_price": pos.price_current,
                "profit": pos.profit,
                "swap": pos.swap,
                "open_time": datetime.fromtimestamp(pos.time)
            }
            for pos in positions
        ]
    
    def get_orders(self) -> list:
        if not self.mt5:
            return []
        orders = self.mt5.orders_get()
        if orders is None:
            return []
        return [{"ticket": o.ticket, "symbol": o.symbol, "type": str(o.type)} for o in orders]

mt5_service = MT5Service()

@router.get("/status")
def get_mt5_status():
    return {
        "available": mt5_service.is_available(),
        "initialized": mt5_service._initialized
    }

@router.post("/accounts", response_model=MT5AccountResponse)
def add_account(data: MT5AccountCreate, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    existing = db.query(MT5Account).filter(
        MT5Account.user_id == current_user.id,
        MT5Account.account_number == data.account_number
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Account already linked")
    
    # Try to connect to MT5
    if mt5_service.is_available():
        try:
            login_int = int(data.account_number)
            success = mt5_service.login(login_int, data.password, data.server)
            if success:
                account_info = mt5_service.get_account_info()
                is_connected = True
            else:
                is_connected = False
        except (ValueError, Exception):
            is_connected = False
    else:
        is_connected = False
    
    account = MT5Account(
        id=str(uuid.uuid4()), user_id=current_user.id,
        broker=data.broker, server=data.server,
        account_number=data.account_number,
        password_hash=hash_password(data.password),
        is_connected=is_connected,
        last_sync=datetime.utcnow() if is_connected else None
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account

@router.get("/accounts", response_model=list[MT5AccountResponse])
def list_accounts(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(MT5Account).filter(MT5Account.user_id == current_user.id).all()

@router.delete("/accounts/{account_id}")
def remove_account(account_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    account = db.query(MT5Account).filter(MT5Account.id == account_id, MT5Account.user_id == current_user.id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    db.delete(account)
    db.commit()
    return {"message": "Account removed"}

@router.get("/accounts/{account_id}/trades", response_model=list[MT5TradeResponse])
def get_trades(account_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    account = db.query(MT5Account).filter(MT5Account.id == account_id, MT5Account.user_id == current_user.id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    # If connected to MT5, sync trades
    if mt5_service.is_available() and account.is_connected:
        try:
            login_int = int(account.account_number)
            mt5_service.login(login_int, "dummy", account.server)  # Will need real password for live sync
            positions = mt5_service.get_positions()
            # Save to database (simplified)
            for pos in positions:
                existing = db.query(MT5Trade).filter(
                    MT5Trade.mt5_account_id == account_id,
                    MT5Trade.ticket == str(pos["ticket"])
                ).first()
                if not existing:
                    trade = MT5Trade(
                        id=str(uuid.uuid4()),
                        mt5_account_id=account_id,
                        ticket=str(pos["ticket"]),
                        pair=pos["symbol"],
                        direction=pos["type"],
                        lots=str(pos["volume"]),
                        open_price=str(pos["open_price"]),
                        pnl=str(pos["profit"]),
                        status="open",
                        synced_at=datetime.utcnow()
                    )
                    db.add(trade)
            db.commit()
        except Exception:
            pass
    
    return db.query(MT5Trade).filter(MT5Trade.mt5_account_id == account_id).order_by(MT5Trade.synced_at.desc()).all()

@router.get("/accounts/{account_id}/status", response_model=SyncStatusResponse)
def get_status(account_id: str, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    account = db.query(MT5Account).filter(MT5Account.id == account_id, MT5Account.user_id == current_user.id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    trades_today = db.query(MT5Trade).filter(
        MT5Trade.mt5_account_id == account_id,
        MT5Trade.synced_at >= today
    ).count()
    
    # Get live account info if connected
    balance = 0
    if mt5_service.is_available() and account.is_connected:
        try:
            login_int = int(account.account_number)
            mt5_service.login(login_int, "dummy", account.server)
            info = mt5_service.get_account_info()
            if info:
                balance = info["balance"]
        except Exception:
            pass
    
    return {
        "is_connected": account.is_connected,
        "last_sync": account.last_sync,
        "trades_today": trades_today,
        "latency_ms": 0,
        "balance": balance
    }

@router.post("/connect-live")
def connect_live(
    account_id: str,
    password: str,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """Connect to live MT5 with real password"""
    account = db.query(MT5Account).filter(
        MT5Account.id == account_id,
        MT5Account.user_id == current_user.id
    ).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    
    if not mt5_service.is_available():
        raise HTTPException(status_code=503, detail="MetaTrader5 not installed")
    
    try:
        login_int = int(account.account_number)
        success = mt5_service.login(login_int, password, account.server)
        if success:
            account.is_connected = True
            account.last_sync = datetime.utcnow()
            db.commit()
            db.refresh(account)
            return {
                "success": True,
                "message": "Connected to MT5",
                "account_info": mt5_service.get_account_info()
            }
        else:
            raise HTTPException(status_code=401, detail="MT5 login failed")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid account number")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
