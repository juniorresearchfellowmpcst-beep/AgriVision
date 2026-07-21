from app.core.database import db

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)

    username = db.Column(db.String(100), unique=True, nullable=False)

    email = db.Column(db.String(120), unique=True, nullable=False)

    password = db.Column(db.String(255), nullable=False)

    created_at = db.Column(db.DateTime, server_default=db.func.now())

    def to_dict(self):
        return {
            'id': self.id,
            'username': self.username,
            'email': self.email,

        }


class UserProfile(db.Model):
    """Extra pilot details kept out of the auth table so the existing users
    schema (and its sqlite file) never needs a migration."""

    __tablename__ = 'user_profiles'

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(
        db.Integer, db.ForeignKey('users.id'), unique=True, nullable=False
    )

    role = db.Column(db.String(50), default='Operator')

    organisation = db.Column(db.String(120), nullable=True)

    phone = db.Column(db.String(30), nullable=True)

    location = db.Column(db.String(120), nullable=True)

    def to_dict(self):
        return {
            'role': self.role,
            'organisation': self.organisation,
            'phone': self.phone,
            'location': self.location,
        }
