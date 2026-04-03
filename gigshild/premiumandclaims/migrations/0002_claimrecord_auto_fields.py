from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("premiumandclaims", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="claimrecord",
            name="auto_created",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="claimrecord",
            name="event_signature",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name="claimrecord",
            name="trigger_source",
            field=models.CharField(blank=True, max_length=32),
        ),
        migrations.AddField(
            model_name="claimrecord",
            name="trigger_title",
            field=models.CharField(blank=True, max_length=255),
        ),
    ]
