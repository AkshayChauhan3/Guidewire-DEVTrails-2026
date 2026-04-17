from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("premiumandclaims", "0003_adaptiveweight"),
    ]

    operations = [
        migrations.AddField(
            model_name="claimrecord",
            name="ai_score",
            field=models.FloatField(default=0.0),
        ),
    ]
