from decimal import Decimal

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("premiumandclaims", "0002_claimrecord_auto_fields"),
    ]

    operations = [
        migrations.CreateModel(
            name="AdaptiveWeight",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("location_key", models.CharField(max_length=128, unique=True)),
                ("weather_weight", models.DecimalField(decimal_places=4, default=Decimal("0.4000"), max_digits=6)),
                ("news_weight", models.DecimalField(decimal_places=4, default=Decimal("0.3000"), max_digits=6)),
                ("location_weight", models.DecimalField(decimal_places=4, default=Decimal("0.2000"), max_digits=6)),
                ("activity_weight", models.DecimalField(decimal_places=4, default=Decimal("0.1000"), max_digits=6)),
                ("last_updated", models.DateTimeField(auto_now=True)),
            ],
        ),
    ]
