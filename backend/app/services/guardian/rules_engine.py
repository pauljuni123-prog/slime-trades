def check_trade_against_rules(trade, rules):
    violations = []
    for rule in rules:
        if not rule.is_active:
            continue
        if rule.rule_type == "max_position_size":
            max_size = rule.settings.get("max_lots", 1.0)
            if trade.get("lots", 0) > max_size:
                violations.append(f"Position size {trade['lots']} exceeds max {max_size}")
        if rule.rule_type == "trading_hours":
            import datetime
            now = datetime.datetime.utcnow().hour
            allowed = rule.settings.get("hours", [9, 10, 11, 12, 13, 14, 15, 16])
            if now not in allowed:
                violations.append(f"Trading outside allowed hours: {allowed}")
        if rule.rule_type == "max_daily_loss":
            daily_loss = rule.settings.get("limit", 100)
            if trade.get("pnl", 0) < -daily_loss:
                violations.append(f"Daily loss limit of {daily_loss} exceeded")
    return violations
