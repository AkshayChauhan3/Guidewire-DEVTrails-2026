from django.core.management.base import BaseCommand
from django.utils import timezone

from premiumandclaims.services import (
    collect_weekly_premium_for_all_partners,
    calculate_or_collect_weekly_premium,
)
from registor_and_login.models import DeliveryPartner


class Command(BaseCommand):
    help = "Collect weekly premium from partner wallets."

    def add_arguments(self, parser):
        parser.add_argument(
            "--phone",
            type=str,
            default="",
            help="Optional phone number to collect premium for one partner.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Preview the premium without deducting money.",
        )

    def handle(self, *args, **options):
        phone = (options["phone"] or "").strip()
        dry_run = options["dry_run"]
        today = timezone.localdate()

        if phone:
            partner = DeliveryPartner.objects.filter(phone=phone).first()
            if not partner:
                self.stderr.write(self.style.ERROR(f"User not found for phone {phone}"))
                return

            result = calculate_or_collect_weekly_premium(
                partner,
                collect=not dry_run,
                today=today,
            )
            status = result["payment_status"]
            amount = result["snapshot"].premium_amount
            action = "previewed" if dry_run else status
            self.stdout.write(
                self.style.SUCCESS(
                    f"Partner {partner.phone}: {action} premium ₹{amount} for week starting {result['snapshot'].week_start}"
                )
            )
            return

        if dry_run:
            partners = DeliveryPartner.objects.order_by("id")
            for partner in partners:
                result = calculate_or_collect_weekly_premium(
                    partner,
                    collect=False,
                    today=today,
                )
                self.stdout.write(
                    f"{partner.phone}: preview ₹{result['snapshot'].premium_amount} "
                    f"(week {result['snapshot'].week_start})"
                )
            return

        summary = collect_weekly_premium_for_all_partners(today=today)
        self.stdout.write(
            self.style.SUCCESS(
                "Weekly premium collection complete: "
                f"{summary['debited']} debited, {summary['already_debited']} already processed, "
                f"{summary['processed']} partners checked."
            )
        )
