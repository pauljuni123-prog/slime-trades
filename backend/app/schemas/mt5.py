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
