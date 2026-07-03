from flask_jwt_extended import create_access_token
from app.api.models.user import User
from app.repositories.user_repository import UserRepository
from app.core.security import hash_password
from app.core.security import verify_password 


class AuthService:

    @staticmethod
    def signup(name, email, password):

        user = UserRepository.get_by_email(email)

        if user:
            return{
                "message": "Email already exists",
            },409
        new_user = User(
            username=name,
            email=email,
            password=hash_password(password)
        )
        UserRepository.create(new_user)
        return {
            "message": "User Registered Successfully",
        },201 
    
    @staticmethod
    def sigin(email,password):
        user = UserRepository.get_by_email(email)

        if not user:
            return {
                "message": "Invalid Email"
            },401
        if not verify_password(user.password, password):
            return {
                "message": "Invalid Password"
            },401
        
        access_token = create_access_token(identity=str(user.id))

        return{
            "access_token": access_token,
            "user":user.to_dict()
            },200