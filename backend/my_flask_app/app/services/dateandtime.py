from datetime import datetime, timezone 

class TimeService:
    @staticmethod
    def now_utc():
        return datetime.now(timezone.utc)
    
    @staticmethod
    def payload():
        now = TimeService.now_utc()
        return {
            "utc_iso":now.isoformat(),
            "epoch_ms": int(now.timestamp()*1000),
            "timezone":"UTC"
        }