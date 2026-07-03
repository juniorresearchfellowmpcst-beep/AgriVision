from flask_bcrypt import Bcrypt

bcrypt = Bcrypt()


def hash_password(password):
    return bcrypt.generate_password_hash(password).decode('utf-8')

def verify_password(hash_password_value, password):
    return bcrypt.check_password_hash(hash_password_value, password)